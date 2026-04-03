const std = @import("std");
const common = @import("common.zig");
const document = @import("document.zig");
const scanner = @import("scanner.zig");
const tables = @import("tables.zig");

pub const ParseOptions = document.ParseOptions;
pub const ParseError = document.ParseError;
pub const ParseMode = document.ParseMode;
pub const NodeType = document.NodeType;
pub const Span = document.Span;
pub const IndexInt = common.IndexInt;
pub const InvalidIndex = common.InvalidIndex;

pub fn Types(comptime options: ParseOptions) type {
    return struct {
        pub const Attribute = struct {
            source: []const u8,
            name: Span,
            value: Span,

            pub fn nameSlice(self: @This()) []const u8 {
                return self.name.slice(self.source);
            }

            pub fn valueRawSlice(self: @This()) []const u8 {
                return self.value.slice(self.source);
            }
        };

        pub const AttributeIterator = struct {
            source: []const u8,
            input: []const u8,
            i: usize,

            pub fn next(self: *@This()) ?Attribute {
                var i = scanner.skipWhitespace(self.input, self.i);
                if (i >= self.input.len or !tables.isNameStart(self.input[i])) {
                    self.i = self.input.len;
                    return null;
                }

                const name_start = i;
                i = scanner.findNameEnd(self.input, i);
                const name_end = i;
                i = scanner.skipWhitespace(self.input, i);

                var value_start = i;
                var value_end = i;
                if (i < self.input.len and self.input[i] == '=') {
                    i += 1;
                    i = scanner.skipWhitespace(self.input, i);
                    if (i < self.input.len) {
                        const quote = self.input[i];
                        if (quote == '\'' or quote == '"') {
                            i += 1;
                            value_start = i;
                            value_end = scanner.findByte(self.input, i, quote) orelse self.input.len;
                            i = if (value_end < self.input.len) value_end + 1 else self.input.len;
                        } else if (options.mode == .turbo) {
                            value_start = i;
                            value_end = scanner.findAttrUnquotedEnd(self.input, i);
                            i = value_end;
                        }
                    }
                }

                self.i = i;
                return .{
                    .source = self.input,
                    .name = .{ .start = @intCast(name_start), .end = @intCast(name_end) },
                    .value = .{ .start = @intCast(value_start), .end = @intCast(value_end) },
                };
            }
        };

        pub const Node = struct {
            source: []const u8,
            kind: NodeType,
            depth: IndexInt,
            name: Span = .{},
            value: Span = .{},
            attr_source: Span = .{},
            token_start: IndexInt = 0,
            token_end: IndexInt = 0,
            content_start: IndexInt = 0,
            self_closing: bool = false,

            pub fn nameSlice(self: @This()) []const u8 {
                return self.name.slice(self.source);
            }

            pub fn valueRawSlice(self: @This()) []const u8 {
                return self.value.slice(self.source);
            }

            pub fn attributes(self: @This()) AttributeIterator {
                return .{
                    .source = self.source,
                    .input = self.attr_source.slice(self.source),
                    .i = 0,
                };
            }

            pub fn getAttributeValueRaw(self: @This(), name: []const u8) ?[]const u8 {
                var it = self.attributes();
                while (it.next()) |attr| {
                    if (std.mem.eql(u8, attr.nameSlice(), name)) return attr.valueRawSlice();
                }
                return null;
            }

            /// Returns the immediate raw text segment after this node's opening token.
            /// For elements that start with another tag, this is empty.
            pub fn leadingTextRaw(self: @This()) []const u8 {
                if (self.kind != .element or self.self_closing) return "";
                const start: usize = self.content_start;
                if (start >= self.source.len or self.source[start] == '<') return "";
                const lt = scanner.findByte(self.source, start, '<') orelse self.source.len;
                return self.source[start..lt];
            }

            /// Computes the raw text directly following this node's subtree.
            /// This scans ahead from the current node, so call it only when needed.
            pub fn followingTextRaw(self: @This()) ParseError![]const u8 {
                const end = try subtreeEndOffset(self.source, self.kind, self.token_start, self.token_end, self.name, self.self_closing);
                if (end >= self.source.len or self.source[end] == '<') return "";
                const lt = scanner.findByte(self.source, end, '<') orelse self.source.len;
                return self.source[end..lt];
            }
        };

        pub const Parser = struct {
            allocator: std.mem.Allocator,
            stack: std.ArrayList(StackEntry) = .empty,
            skip_stack: std.ArrayList(StackEntry) = .empty,

            const Self = @This();
            const strict_mode = options.mode == .strict;
            const validate_closing_tags = options.validate_closing_tags;
            const require_closed_elements_on_eof = options.require_closed_elements_on_eof;
            const drop_whitespace_text_nodes = options.drop_whitespace_text_nodes;
            const include_misc_nodes = options.include_misc_nodes;

            pub fn init(allocator: std.mem.Allocator) Parser {
                return .{ .allocator = allocator };
            }

            pub fn deinit(self: *Self) void {
                self.stack.deinit(self.allocator);
                self.skip_stack.deinit(self.allocator);
            }

            pub fn parse(noalias self: *Self, noalias input: []const u8, ctx: anytype, comptime callback: anytype) ParseError!void {
                if (!common.lenFits(input.len)) return error.InputTooLarge;
                self.stack.items.len = 0;
                self.skip_stack.items.len = 0;
                try self.reserveForInput(input.len);

                var i: usize = 0;
                while (i < input.len) {
                    if (input[i] != '<') {
                        const run = scanner.scanTextRun(input, i);
                        if (run.lt_index > i and (!drop_whitespace_text_nodes or run.has_non_whitespace)) {
                            const node: Node = .{
                                .source = input,
                                .kind = .text,
                                .depth = @intCast(self.stack.items.len),
                                .value = .{ .start = @intCast(i), .end = @intCast(run.lt_index) },
                                .token_start = @intCast(i),
                                .token_end = @intCast(run.lt_index),
                            };
                            _ = callCallback(ctx, callback, node);
                        }
                        i = run.lt_index;
                        continue;
                    }

                    if (i + 1 >= input.len) {
                        if (strict_mode) return error.UnexpectedEndOfData;
                        break;
                    }

                    switch (input[i + 1]) {
                        '/' => i = try self.parseClosingTag(input, i),
                        '?' => i = try self.parsePiOrDeclaration(input, i, ctx, callback),
                        '!' => i = try self.parseBangNode(input, i, ctx, callback),
                        else => i = try self.parseOpeningTag(input, i, ctx, callback),
                    }
                }

                if (require_closed_elements_on_eof and self.stack.items.len != 0) return error.UnexpectedEndOfData;
                if (validate_closing_tags and self.stack.items.len != 0) return error.UnexpectedEndOfData;
            }

            fn reserveForInput(self: *Self, input_len: usize) !void {
                const est_stack = @max(@as(usize, 8), input_len / 512 + 8);
                if (est_stack > self.stack.capacity) try self.stack.ensureTotalCapacity(self.allocator, est_stack);
                if (est_stack > self.skip_stack.capacity) try self.skip_stack.ensureTotalCapacity(self.allocator, est_stack);
            }

            fn parseOpeningTag(noalias self: *Self, input: []const u8, start: usize, ctx: anytype, comptime callback: anytype) ParseError!usize {
                var i = start + 1;
                if (i >= input.len) return error.UnexpectedEndOfData;
                if (!tables.isNameStart(input[i])) {
                    if (strict_mode) return error.ExpectedElementName;
                    const gt = scanner.findByte(input, i, '>') orelse input.len;
                    return if (gt < input.len) gt + 1 else gt;
                }

                const name_start = i;
                const scan = scanner.scanNameAndKey(input, i);
                i = scan.end;
                const attr_start = i;
                var attr_end = i;
                var self_closing = false;

                while (i < input.len) {
                    i = skipWs(input, i);
                    if (i >= input.len) return error.UnexpectedEndOfData;
                    const c = input[i];
                    if (c == '>') {
                        attr_end = i;
                        i += 1;
                        break;
                    }
                    if (c == '/' and i + 1 < input.len and input[i + 1] == '>') {
                        attr_end = i;
                        i += 2;
                        self_closing = true;
                        break;
                    }
                    i = try self.skipAttribute(input, i);
                }
                if (i > input.len) return error.UnexpectedEndOfData;

                const node: Node = .{
                    .source = input,
                    .kind = .element,
                    .depth = @intCast(self.stack.items.len),
                    .name = .{ .start = @intCast(name_start), .end = @intCast(scan.end) },
                    .attr_source = .{ .start = @intCast(attr_start), .end = @intCast(attr_end) },
                    .token_start = @intCast(start),
                    .token_end = @intCast(i),
                    .content_start = @intCast(i),
                    .self_closing = self_closing,
                };

                const descend = callCallback(ctx, callback, node);
                if (self_closing) return i;
                if (!descend) return try self.skipSubtree(input, i, scan, .{ .start = @intCast(name_start), .end = @intCast(scan.end) });
                if (try self.tryFinishSimpleTextElement(input, i, name_start, scan, ctx, callback)) |next| return next;

                try self.pushStack(.{
                    .name = .{ .start = @intCast(name_start), .end = @intCast(scan.end) },
                    .key = scan.key,
                    .len = scan.len,
                });
                return i;
            }

            fn skipAttribute(noalias self: *Self, input: []const u8, start: usize) ParseError!usize {
                _ = self;
                if (!tables.isNameStart(input[start])) {
                    if (strict_mode) return error.ExpectedAttributeName;
                    return start + 1;
                }
                var i = scanner.findNameEnd(input, start);
                i = skipWs(input, i);
                if (i >= input.len or input[i] != '=') {
                    if (strict_mode) return error.ExpectedEq;
                    return i;
                }
                i += 1;
                i = skipWs(input, i);
                if (i >= input.len) return error.UnexpectedEndOfData;
                const quote = input[i];
                if (quote == '\'' or quote == '"') {
                    const end = scanner.findByte(input, i + 1, quote) orelse {
                        if (strict_mode) return error.ExpectedQuote;
                        return input.len;
                    };
                    return end + 1;
                }
                if (strict_mode) return error.ExpectedQuote;
                const raw_end = scanner.findAttrUnquotedEnd(input, i);
                if (raw_end > i and raw_end < input.len and input[raw_end] == '>' and input[raw_end - 1] == '/') {
                    return raw_end - 1;
                }
                return raw_end;
            }

            fn parseClosingTag(noalias self: *Self, input: []const u8, start: usize) ParseError!usize {
                var i = start + 2;
                if (i < input.len and tables.isWhitespace(input[i])) i = skipWs(input, i);
                if (i >= input.len) {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    return input.len;
                }
                if (!tables.isNameStart(input[i])) {
                    if (validate_closing_tags) return error.InvalidClosingTagName;
                    const gt = scanner.findByte(input, i, '>') orelse input.len;
                    return if (gt < input.len) gt + 1 else gt;
                }
                const scan = scanner.scanNameAndKey(input, i);
                i = scan.end;
                if (i < input.len and tables.isWhitespace(input[i])) i = skipWs(input, i);
                if (i >= input.len) {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    return input.len;
                }
                if (input[i] != '>') return error.InvalidClosingTagName;
                i += 1;

                if (self.stack.items.len == 0) {
                    if (validate_closing_tags) return error.InvalidClosingTagName;
                    return i;
                }

                if (validate_closing_tags) {
                    const top = self.stack.items[self.stack.items.len - 1];
                    if (top.len != scan.len or top.key != scan.key) return error.InvalidClosingTagName;
                    if (scan.len > 8 and !std.mem.eql(u8, top.name.slice(input)[8..], input[@as(usize, @intCast(top.name.start)) + 8 .. scan.end])) {
                        return error.InvalidClosingTagName;
                    }
                }
                self.stack.items.len -= 1;
                return i;
            }

            fn parsePiOrDeclaration(noalias self: *Self, input: []const u8, start: usize, ctx: anytype, comptime callback: anytype) ParseError!usize {
                var i = start + 2;
                if (i >= input.len or !tables.isNameStart(input[i])) {
                    if (strict_mode) return error.ExpectedPiTarget;
                    const end0 = scanner.findSequence(input, i, "?>") orelse input.len;
                    return if (end0 < input.len) end0 + 2 else end0;
                }

                const target_start = i;
                i = scanner.findNameEnd(input, i);
                const target_end = i;
                i = skipWs(input, i);
                const value_start = i;
                const end = scanner.findSequence(input, i, "?>") orelse {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    return input.len;
                };
                if (include_misc_nodes) {
                    const decl = target_end - target_start == 3 and
                        ((input[target_start] | 0x20) == 'x') and
                        ((input[target_start + 1] | 0x20) == 'm') and
                        ((input[target_start + 2] | 0x20) == 'l');
                    _ = callCallback(ctx, callback, Node{
                        .source = input,
                        .kind = if (decl) .declaration else .pi,
                        .depth = @intCast(self.stack.items.len),
                        .name = .{ .start = @intCast(target_start), .end = @intCast(target_end) },
                        .value = .{ .start = @intCast(value_start), .end = @intCast(end) },
                        .token_start = @intCast(start),
                        .token_end = @intCast(end + 2),
                    });
                }
                return end + 2;
            }

            fn parseBangNode(noalias self: *Self, input: []const u8, start: usize, ctx: anytype, comptime callback: anytype) ParseError!usize {
                if (start + 3 < input.len and input[start + 2] == '-' and input[start + 3] == '-') {
                    const value_start = start + 4;
                    const end = scanner.findSequence(input, value_start, "-->") orelse {
                        if (strict_mode) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    if (include_misc_nodes) {
                        _ = callCallback(ctx, callback, Node{
                            .source = input,
                            .kind = .comment,
                            .depth = @intCast(self.stack.items.len),
                            .value = .{ .start = @intCast(value_start), .end = @intCast(end) },
                            .token_start = @intCast(start),
                            .token_end = @intCast(end + 3),
                        });
                    }
                    return end + 3;
                }
                if (start + 8 < input.len and input[start + 2] == '[' and input[start + 3] == 'C' and input[start + 4] == 'D' and input[start + 5] == 'A' and input[start + 6] == 'T' and input[start + 7] == 'A' and input[start + 8] == '[') {
                    const value_start = start + 9;
                    const end = scanner.findSequence(input, value_start, "]]>") orelse {
                        if (strict_mode) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    if (include_misc_nodes) {
                        _ = callCallback(ctx, callback, Node{
                            .source = input,
                            .kind = .cdata,
                            .depth = @intCast(self.stack.items.len),
                            .value = .{ .start = @intCast(value_start), .end = @intCast(end) },
                            .token_start = @intCast(start),
                            .token_end = @intCast(end + 3),
                        });
                    }
                    return end + 3;
                }
                if (isDoctype(input, start)) {
                    const end = findDoctypeEnd(input, start + 9) orelse {
                        if (strict_mode) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    if (include_misc_nodes) {
                        _ = callCallback(ctx, callback, Node{
                            .source = input,
                            .kind = .doctype,
                            .depth = @intCast(self.stack.items.len),
                            .value = .{ .start = @intCast(start + 9), .end = @intCast(end) },
                            .token_start = @intCast(start),
                            .token_end = @intCast(end + 1),
                        });
                    }
                    return end + 1;
                }
                if (strict_mode) return error.ExpectedGt;
                const gt = scanner.findByte(input, start, '>') orelse input.len;
                return if (gt < input.len) gt + 1 else gt;
            }

            fn skipSubtree(noalias self: *Self, input: []const u8, start: usize, root_scan: scanner.NameScan, root_name: Span) ParseError!usize {
                var i = start;
                if (!validate_closing_tags) {
                    var depth: usize = 1;
                    while (i < input.len) {
                        const lt = scanner.findByte(input, i, '<') orelse return if (strict_mode) error.UnexpectedEndOfData else input.len;
                        i = lt;
                        if (i + 1 >= input.len) return if (strict_mode) error.UnexpectedEndOfData else input.len;
                        switch (input[i + 1]) {
                            '/' => {
                                i = try skipClosingTag(input, i);
                                depth -= 1;
                                if (depth == 0) return i;
                            },
                            '?' => i = try skipPi(input, i),
                            '!' => i = try skipBang(input, i),
                            else => {
                                const open = try skipOpeningTagToken(input, i);
                                i = open.next;
                                if (!open.self_closing) depth += 1;
                            },
                        }
                    }
                    return if (strict_mode) error.UnexpectedEndOfData else input.len;
                }

                self.skip_stack.items.len = 0;
                try self.skip_stack.append(self.allocator, .{ .name = root_name, .key = root_scan.key, .len = root_scan.len });
                while (i < input.len) {
                    const lt = scanner.findByte(input, i, '<') orelse return error.UnexpectedEndOfData;
                    i = lt;
                    if (i + 1 >= input.len) return error.UnexpectedEndOfData;
                    switch (input[i + 1]) {
                        '/' => {
                            const close = try scanClosingTag(input, i);
                            const top = self.skip_stack.items[self.skip_stack.items.len - 1];
                            if (top.len != close.scan.len or top.key != close.scan.key) return error.InvalidClosingTagName;
                            if (close.scan.len > 8 and !std.mem.eql(u8, top.name.slice(input)[8..], input[close.name_start + 8 .. close.scan.end])) return error.InvalidClosingTagName;
                            self.skip_stack.items.len -= 1;
                            i = close.next;
                            if (self.skip_stack.items.len == 0) return i;
                        },
                        '?' => i = try skipPi(input, i),
                        '!' => i = try skipBang(input, i),
                        else => {
                            const open = try scanOpeningTagToken(input, i);
                            i = open.next;
                            if (!open.self_closing) try self.skip_stack.append(self.allocator, .{ .name = .{ .start = @intCast(open.name_start), .end = @intCast(open.scan.end) }, .key = open.scan.key, .len = open.scan.len });
                        },
                    }
                }
                return error.UnexpectedEndOfData;
            }

            fn tryFinishSimpleTextElement(
                noalias self: *Self,
                input: []const u8,
                content_start: usize,
                name_start: usize,
                open_scan: scanner.NameScan,
                ctx: anytype,
                comptime callback: anytype,
            ) ParseError!?usize {
                if (content_start >= input.len or input[content_start] == '<') return null;

                const lt = scanner.findByte(input, content_start, '<') orelse return null;
                if (lt == content_start or lt + 2 >= input.len or input[lt + 1] != '/') return null;

                const close_start = lt + 2;
                const close_end = close_start + open_scan.len;
                if (close_end > input.len) return null;
                if (scanner.prefixKey(input[close_start..close_end]) != open_scan.key) return null;
                if (open_scan.len > 8 and !std.mem.eql(u8, input[name_start + 8 .. name_start + open_scan.len], input[close_start + 8 .. close_end])) return null;

                var j = close_end;
                if (j >= input.len) {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    return null;
                }
                if (input[j] == '>') {
                    j += 1;
                } else if (tables.isWhitespace(input[j])) {
                    j = skipWs(input, j);
                    if (j >= input.len) {
                        if (strict_mode) return error.UnexpectedEndOfData;
                        return null;
                    }
                    if (input[j] != '>') return null;
                    j += 1;
                } else {
                    return null;
                }

                const raw = input[content_start..lt];
                if (drop_whitespace_text_nodes and isWhitespaceOnly(raw)) return j;

                _ = callCallback(ctx, callback, Node{
                    .source = input,
                    .kind = .text,
                    .depth = @intCast(self.stack.items.len + 1),
                    .value = .{ .start = @intCast(content_start), .end = @intCast(lt) },
                    .token_start = @intCast(content_start),
                    .token_end = @intCast(lt),
                });
                return j;
            }

            fn pushStack(noalias self: *Self, entry: StackEntry) ParseError!void {
                const len = self.stack.items.len;
                if (len == self.stack.capacity) self.stack.ensureTotalCapacityPrecise(self.allocator, len + len / 2 + 8) catch return error.OutOfMemory;
                self.stack.appendAssumeCapacity(entry);
            }
        };

        const StackEntry = struct {
            name: Span,
            key: u64,
            len: u16,
        };

    };
}

fn callCallback(ctx: anytype, comptime callback: anytype, node: anytype) bool {
    const cb_info = @typeInfo(@TypeOf(callback)).@"fn";
    return switch (cb_info.params.len) {
        1 => @call(.auto, callback, .{node}),
        2 => @call(.auto, callback, .{ ctx, node }),
        else => @compileError("streaming callback must take (node) or (ctx, node) and return bool"),
    };
}

fn skipWs(input: []const u8, start: usize) usize {
    if (start >= input.len) return start;
    const c = input[start];
    if (!tables.isWhitespace(c)) return start;
    return scanner.skipWhitespace(input, start);
}

fn isWhitespaceOnly(raw: []const u8) bool {
    if (raw.len == 0) return true;
    for (raw) |c| {
        if (!tables.isWhitespace(c)) return false;
    }
    return true;
}

fn subtreeEndOffset(input: []const u8, kind: NodeType, token_start: IndexInt, token_end: IndexInt, name: Span, self_closing: bool) ParseError!usize {
    const start: usize = token_start;
    const end: usize = token_end;
    switch (kind) {
        .text, .comment, .cdata, .pi, .declaration, .doctype => return end,
        .element => {
            if (self_closing) return end;
            _ = name;
            return skipSubtreeStateless(input, end);
        },
        .document => return start,
    }
}

fn skipSubtreeStateless(input: []const u8, start: usize) ParseError!usize {
    var depth: usize = 1;
    var i = start;
    while (i < input.len) {
        const lt = scanner.findByte(input, i, '<') orelse return error.UnexpectedEndOfData;
        i = lt;
        if (i + 1 >= input.len) return error.UnexpectedEndOfData;
        switch (input[i + 1]) {
            '/' => {
                i = try skipClosingTag(input, i);
                depth -= 1;
                if (depth == 0) return i;
            },
            '?' => i = try skipPi(input, i),
            '!' => i = try skipBang(input, i),
            else => {
                const open = try skipOpeningTagToken(input, i);
                i = open.next;
                if (!open.self_closing) depth += 1;
            },
        }
    }
    return error.UnexpectedEndOfData;
}

const SkipOpen = struct {
    next: usize,
    self_closing: bool,
};

const OpenToken = struct {
    next: usize,
    self_closing: bool,
    name_start: usize,
    scan: scanner.NameScan,
};

const CloseToken = struct {
    next: usize,
    name_start: usize,
    scan: scanner.NameScan,
};

fn skipOpeningTagToken(input: []const u8, start: usize) ParseError!SkipOpen {
    const open = try scanOpeningTagToken(input, start);
    return .{ .next = open.next, .self_closing = open.self_closing };
}

fn scanOpeningTagToken(input: []const u8, start: usize) ParseError!OpenToken {
    var i = start + 1;
    if (i >= input.len or !tables.isNameStart(input[i])) return error.ExpectedElementName;
    const name_start = i;
    const scan = scanner.scanNameAndKey(input, i);
    i = scan.end;
    while (i < input.len) {
        i = skipWs(input, i);
        if (i >= input.len) return error.UnexpectedEndOfData;
        const c = input[i];
        if (c == '>') return .{ .next = i + 1, .self_closing = false, .name_start = name_start, .scan = scan };
        if (c == '/' and i + 1 < input.len and input[i + 1] == '>') return .{ .next = i + 2, .self_closing = true, .name_start = name_start, .scan = scan };
        if (!tables.isNameStart(c)) return error.ExpectedAttributeName;
        i = scanner.findNameEnd(input, i);
        i = skipWs(input, i);
        if (i >= input.len or input[i] != '=') return error.ExpectedEq;
        i += 1;
        i = skipWs(input, i);
        if (i >= input.len) return error.UnexpectedEndOfData;
        const quote = input[i];
        if (quote != '\'' and quote != '"') return error.ExpectedQuote;
        i = (scanner.findByte(input, i + 1, quote) orelse return error.ExpectedQuote) + 1;
    }
    return error.UnexpectedEndOfData;
}

fn scanClosingTag(input: []const u8, start: usize) ParseError!CloseToken {
    var i = start + 2;
    if (i < input.len and tables.isWhitespace(input[i])) i = skipWs(input, i);
    if (i >= input.len or !tables.isNameStart(input[i])) return error.InvalidClosingTagName;
    const name_start = i;
    const scan = scanner.scanNameAndKey(input, i);
    i = scan.end;
    if (i < input.len and tables.isWhitespace(input[i])) i = skipWs(input, i);
    if (i >= input.len or input[i] != '>') return error.InvalidClosingTagName;
    return .{ .next = i + 1, .name_start = name_start, .scan = scan };
}

fn skipClosingTag(input: []const u8, start: usize) ParseError!usize {
    return (try scanClosingTag(input, start)).next;
}

fn skipPi(input: []const u8, start: usize) ParseError!usize {
    const end = scanner.findSequence(input, start + 2, "?>") orelse return error.UnexpectedEndOfData;
    return end + 2;
}

fn skipBang(input: []const u8, start: usize) ParseError!usize {
    if (start + 3 < input.len and input[start + 2] == '-' and input[start + 3] == '-') {
        const end = scanner.findSequence(input, start + 4, "-->") orelse return error.UnexpectedEndOfData;
        return end + 3;
    }
    if (start + 8 < input.len and input[start + 2] == '[' and input[start + 3] == 'C' and input[start + 4] == 'D' and input[start + 5] == 'A' and input[start + 6] == 'T' and input[start + 7] == 'A' and input[start + 8] == '[') {
        const end = scanner.findSequence(input, start + 9, "]]>") orelse return error.UnexpectedEndOfData;
        return end + 3;
    }
    if (isDoctype(input, start)) {
        const end = findDoctypeEnd(input, start + 9) orelse return error.UnexpectedEndOfData;
        return end + 1;
    }
    return error.ExpectedGt;
}

fn isDoctype(input: []const u8, start: usize) bool {
    return start + 9 <= input.len and
        input[start] == '<' and
        input[start + 1] == '!' and
        ((input[start + 2] | 0x20) == 'd') and
        ((input[start + 3] | 0x20) == 'o') and
        ((input[start + 4] | 0x20) == 'c') and
        ((input[start + 5] | 0x20) == 't') and
        ((input[start + 6] | 0x20) == 'y') and
        ((input[start + 7] | 0x20) == 'p') and
        ((input[start + 8] | 0x20) == 'e');
}

fn findDoctypeEnd(input: []const u8, start: usize) ?usize {
    var j = start;
    var bracket_depth: i32 = 0;
    var quote: u8 = 0;
    while (j < input.len) : (j += 1) {
        const c = input[j];
        if (quote != 0) {
            if (c == quote) quote = 0;
            continue;
        }
        if (c == '\'' or c == '"') {
            quote = c;
            continue;
        }
        if (c == '[') {
            bracket_depth += 1;
            continue;
        }
        if (c == ']') {
            if (bracket_depth > 0) bracket_depth -= 1;
            continue;
        }
        if (c == '>' and bracket_depth == 0) return j;
    }
    return null;
}
