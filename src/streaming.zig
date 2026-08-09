const std = @import("std");
const common = @import("common.zig");
const document = @import("document.zig");
const scanner = @import("scanner.zig");
const tables = @import("tables.zig");

const ParseOptions = document.ParseOptions;
const ParseError = document.ParseError;
const NodeType = document.NodeType;
const Span = document.Span;
const IndexInt = common.IndexInt;

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
            /// Value span for non-elements; raw attribute-source span for elements.
            data: Span = .{},
            token_end: IndexInt = 0,
            self_closing: bool = false,

            pub fn nameSlice(self: @This()) []const u8 {
                return self.name.slice(self.source);
            }

            pub fn valueRawSlice(self: @This()) []const u8 {
                return self.data.slice(self.source);
            }

            pub fn attributes(self: @This()) AttributeIterator {
                return .{
                    .input = self.data.slice(self.source),
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
                const start: usize = self.token_end;
                if (start >= self.source.len or self.source[start] == '<') return "";
                const lt = scanner.findByte(self.source, start, '<') orelse self.source.len;
                return self.source[start..lt];
            }

            /// Computes the raw text directly following this node's subtree.
            /// This scans ahead from the current node, so call it only when needed.
            pub fn followingTextRaw(self: @This()) ParseError![]const u8 {
                const end = try subtreeEndOffset(self.source, self.kind, self.token_end, self.self_closing);
                if (end >= self.source.len or self.source[end] == '<') return "";
                const lt = scanner.findByte(self.source, end, '<') orelse self.source.len;
                return self.source[end..lt];
            }
        };

        const StackEntry = struct {
            name: Span,
            key: u64,
        };
        const Stack = if (options.validate_closing_tags) std.ArrayList(StackEntry) else usize;
        const Allocator = if (options.validate_closing_tags) std.mem.Allocator else void;

        pub const Parser = struct {
            allocator: Allocator,
            stack: Stack = if (options.validate_closing_tags) .empty else 0,
            skip_stack: Stack = if (options.validate_closing_tags) .empty else 0,
            offset: usize = 0,
            needs_more: bool = false,

            const Self = @This();
            const strict_mode = options.mode == .strict;
            const validate_closing_tags = options.validate_closing_tags;
            const require_closed_elements_on_eof = options.require_closed_elements_on_eof;
            const drop_whitespace_text_nodes = options.drop_whitespace_text_nodes;
            const include_misc_nodes = options.include_misc_nodes;

            pub const State = struct {
                offset: usize,
                stack_len: usize,
                skip_stack_len: usize,
                needs_more: bool,
            };

            pub fn init(allocator: std.mem.Allocator) Parser {
                return .{ .allocator = if (comptime validate_closing_tags) allocator else {} };
            }

            pub fn deinit(self: *Self) void {
                if (comptime validate_closing_tags) {
                    self.stack.deinit(self.allocator);
                    self.skip_stack.deinit(self.allocator);
                }
            }

            pub fn parse(noalias self: *Self, noalias input: []const u8, ctx: anytype, comptime callback: anytype) ParseError!void {
                if (!common.lenFits(input.len)) return error.InputTooLarge;
                self.clearStacks();
                self.offset = 0;
                self.needs_more = false;
                try self.reserveForInput(input.len);

                var i: usize = self.offset;
                while (i < input.len) {
                    if (input[i] != '<') {
                        if (drop_whitespace_text_nodes and tables.WhitespaceTable[input[i]]) {
                            const next = scanner.skipWhitespace(input, i);
                            if (next >= input.len) {
                                i = next;
                                continue;
                            }
                            if (input[next] == '<') {
                                i = next;
                                continue;
                            }
                        }
                        const run = scanner.scanTextRun(input, i);
                        if (run.lt_index > i and (!drop_whitespace_text_nodes or run.has_non_whitespace)) {
                            const node: Node = .{
                                .source = input,
                                .kind = .text,
                                .depth = @intCast(self.stackLen()),
                                .data = .{ .start = @intCast(i), .end = @intCast(run.lt_index) },
                                .token_end = @intCast(run.lt_index),
                            };
                            _ = callCallback(ctx, callback, &node);
                        }
                        i = run.lt_index;
                        continue;
                    }

                    if (i + 1 >= input.len) {
                        if (strict_mode) return error.UnexpectedEndOfData;
                        break;
                    }

                    switch (input[i + 1]) {
                        '/' => i = try self.parseClosingTag(input, i, false),
                        '?' => i = try self.parsePiOrDeclaration(input, i, ctx, callback, false),
                        '!' => i = try self.parseBangNode(input, i, ctx, callback, false),
                        else => i = try self.parseOpeningTag(input, i, ctx, callback, false),
                    }
                }

                if (require_closed_elements_on_eof and self.stackLen() != 0) return error.UnexpectedEndOfData;
                self.offset = i;
            }

            pub fn clear(self: *Self) void {
                self.clearStacks();
                self.offset = 0;
                self.needs_more = false;
            }

            pub fn save(self: *const Self) State {
                return .{
                    .offset = self.offset,
                    .stack_len = self.stackLen(),
                    .skip_stack_len = self.skipStackLen(),
                    .needs_more = self.needs_more,
                };
            }

            pub fn restore(self: *Self, state: State) void {
                self.offset = state.offset;
                self.restoreStackLen(state.stack_len);
                self.restoreSkipStackLen(state.skip_stack_len);
                self.needs_more = state.needs_more;
            }

            pub fn parseAvailable(noalias self: *Self, noalias input: []const u8, ctx: anytype, comptime callback: anytype) ParseError!bool {
                if (!common.lenFits(input.len)) return error.InputTooLarge;
                try self.reserveForInput(input.len);
                if (self.offset > input.len) return error.UnexpectedEndOfData;
                self.needs_more = false;

                while (self.offset < input.len) {
                    if (self.skipStackLen() != 0) {
                        const progress = try self.walkSkipped(input, self.offset, true);
                        self.offset = progress.next;
                        if (progress.needs_more) {
                            self.needs_more = true;
                            return false;
                        }
                        continue;
                    }
                    if (drop_whitespace_text_nodes and tables.WhitespaceTable[input[self.offset]]) {
                        const next = scanner.skipWhitespace(input, self.offset);
                        if (next >= input.len) {
                            // Keep a trailing whitespace run pending: a later
                            // cumulative chunk may extend this same text node
                            // with non-whitespace bytes. `finish` may safely
                            // discard it when it really is the final run.
                            return true;
                        }
                        if (input[next] == '<') {
                            self.offset = next;
                            continue;
                        }
                    }
                    const checkpoint = self.save();
                    const next = self.parseOne(input, self.offset, ctx, callback, true) catch |err| switch (err) {
                        error.UnexpectedEndOfData => {
                            self.restore(checkpoint);
                            self.needs_more = true;
                            return false;
                        },
                        else => |e| return e,
                    };
                    self.offset = next;
                }
                return true;
            }

            pub fn finish(self: *Self) ParseError!void {
                if (self.needs_more) return error.UnexpectedEndOfData;
                if (require_closed_elements_on_eof and (self.stackLen() != 0 or self.skipStackLen() != 0)) return error.UnexpectedEndOfData;
            }

            inline fn parseOne(noalias self: *Self, input: []const u8, start: usize, ctx: anytype, comptime callback: anytype, comptime incremental: bool) ParseError!usize {
                const i = start;
                if (input[i] != '<') {
                    if (drop_whitespace_text_nodes and tables.WhitespaceTable[input[i]]) {
                        const next = scanner.skipWhitespace(input, i);
                        if (next >= input.len) return next;
                        if (input[next] == '<') return next;
                    }
                    const run = scanner.scanTextRun(input, i);
                    if (run.lt_index > i and (!drop_whitespace_text_nodes or run.has_non_whitespace)) {
                        const node: Node = .{
                            .source = input,
                            .kind = .text,
                            .depth = @intCast(self.stackLen()),
                            .data = .{ .start = @intCast(i), .end = @intCast(run.lt_index) },
                            .token_end = @intCast(run.lt_index),
                        };
                        _ = callCallback(ctx, callback, &node);
                    }
                    return run.lt_index;
                }
                if (i + 1 >= input.len) {
                    if (!incremental and !strict_mode) return input.len;
                    return error.UnexpectedEndOfData;
                }
                return switch (input[i + 1]) {
                    '/' => try self.parseClosingTag(input, i, incremental),
                    '?' => try self.parsePiOrDeclaration(input, i, ctx, callback, incremental),
                    '!' => try self.parseBangNode(input, i, ctx, callback, incremental),
                    else => try self.parseOpeningTag(input, i, ctx, callback, incremental),
                };
            }

            inline fn reserveForInput(self: *Self, input_len: usize) !void {
                if (comptime validate_closing_tags) {
                    const est_stack = @max(@as(usize, 8), input_len / 512 + 8);
                    if (est_stack > self.stack.capacity) try self.stack.ensureTotalCapacity(self.allocator, est_stack);
                }
            }

            fn parseOpeningTag(noalias self: *Self, input: []const u8, start: usize, ctx: anytype, comptime callback: anytype, comptime incremental: bool) ParseError!usize {
                var i = start + 1;
                if (i >= input.len) return error.UnexpectedEndOfData;
                if (!tables.isNameStart(input[i])) {
                    if (strict_mode) return error.ExpectedElementName;
                    const gt = scanner.findByte(input, i, '>') orelse {
                        if (incremental) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    return gt + 1;
                }

                const name_start = i;
                const name_scan = scanner.scanNameAndKey(input, i);
                const name_end = name_scan.end;
                i = name_end;
                const name = Span{ .start = @intCast(name_start), .end = @intCast(name_end) };
                const attr_start = i;
                var attr_end = i;
                var self_closing = false;
                var closed = false;

                while (i < input.len) {
                    const boundary = i;
                    i = skipWs(input, i);
                    if (i >= input.len) return error.UnexpectedEndOfData;
                    const c = input[i];
                    if (c == '>') {
                        attr_end = i;
                        i += 1;
                        closed = true;
                        break;
                    }
                    if (c == '/' and i + 1 < input.len and input[i + 1] == '>') {
                        attr_end = i;
                        i += 2;
                        self_closing = true;
                        closed = true;
                        break;
                    }
                    if (incremental and c == '/' and i + 1 >= input.len) return error.UnexpectedEndOfData;
                    if (strict_mode and i == boundary) {
                        @branchHint(.unlikely);
                        return error.ExpectedAttributeName;
                    }
                    if (!tables.isNameStart(c)) {
                        if (strict_mode) return error.ExpectedAttributeName;
                        i += 1;
                        continue;
                    }

                    var attr_i = scanner.findNameEnd(input, i);
                    if (attr_i + 1 < input.len and input[attr_i] == '=') {
                        const quote = input[attr_i + 1];
                        if (quote == '\'' or quote == '"') {
                            i = (scanner.findByte(input, attr_i + 2, quote) orelse {
                                if (incremental) return error.UnexpectedEndOfData;
                                if (strict_mode) return error.ExpectedQuote;
                                return input.len;
                            }) + 1;
                            continue;
                        }
                    }

                    attr_i = skipWs(input, attr_i);
                    if (attr_i >= input.len) return error.UnexpectedEndOfData;
                    if (input[attr_i] != '=') {
                        if (strict_mode) {
                            @branchHint(.unlikely);
                            return error.ExpectedEq;
                        }
                        i = attr_i;
                        continue;
                    }
                    attr_i += 1;
                    attr_i = skipWs(input, attr_i);
                    if (attr_i >= input.len) return error.UnexpectedEndOfData;
                    const quote = input[attr_i];
                    if (quote == '\'' or quote == '"') {
                        i = (scanner.findByte(input, attr_i + 1, quote) orelse {
                            if (incremental) return error.UnexpectedEndOfData;
                            if (strict_mode) return error.ExpectedQuote;
                            return input.len;
                        }) + 1;
                        continue;
                    }
                    if (strict_mode) return error.ExpectedQuote;
                    const raw_end = scanner.findAttrUnquotedEnd(input, attr_i);
                    if (raw_end > attr_i and raw_end < input.len and input[raw_end] == '>' and input[raw_end - 1] == '/') {
                        i = raw_end - 1;
                    } else {
                        i = raw_end;
                    }
                }
                if (!closed) return error.UnexpectedEndOfData;

                const node: Node = .{
                    .source = input,
                    .kind = .element,
                    .depth = @intCast(self.stackLen()),
                    .name = name,
                    .data = .{ .start = @intCast(attr_start), .end = @intCast(attr_end) },
                    .token_end = @intCast(i),
                    .self_closing = self_closing,
                };

                const descend = callCallback(ctx, callback, &node);
                if (self_closing) return i;
                if (!descend) {
                    if (incremental) {
                        try self.beginSkip(name, name_scan.key);
                        return i;
                    }
                    return try self.skipSubtree(input, i, name, name_scan.key);
                }
                if (!incremental) {
                    if (try self.tryFinishSimpleTextElement(input, i, name, name_scan.key, ctx, callback)) |next| return next;
                }

                try self.pushStack(name, name_scan.key);
                return i;
            }

            fn parseClosingTag(noalias self: *Self, input: []const u8, start: usize, comptime incremental: bool) ParseError!usize {
                if (!validate_closing_tags) {
                    const gt = scanner.findByte(input, start + 2, '>') orelse {
                        if (incremental) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    if (self.stackLen() != 0) self.popStack();
                    return gt + 1;
                }

                var i = start + 2;
                if (i < input.len and tables.isWhitespace(input[i])) {
                    if (strict_mode) return error.InvalidClosingTagName;
                    i = skipWs(input, i);
                }
                if (i >= input.len) {
                    if (strict_mode or incremental) return error.UnexpectedEndOfData;
                    return input.len;
                }
                if (!tables.isNameStart(input[i])) {
                    if (validate_closing_tags) return error.InvalidClosingTagName;
                    const gt = scanner.findByte(input, i, '>') orelse input.len;
                    return if (gt < input.len) gt + 1 else gt;
                }
                const name_start = i;
                const name_scan = scanner.scanNameAndKey(input, i);
                const name_end = name_scan.end;
                i = name_end;
                if (i < input.len and tables.isWhitespace(input[i])) i = skipWs(input, i);
                if (i >= input.len) {
                    if (strict_mode or incremental) return error.UnexpectedEndOfData;
                    return input.len;
                }
                if (input[i] != '>') return error.InvalidClosingTagName;
                i += 1;

                if (self.stackLen() == 0) {
                    if (validate_closing_tags) return error.InvalidClosingTagName;
                    return i;
                }

                if (validate_closing_tags) {
                    const top = self.topStack();
                    const close_len = name_end - name_start;
                    if (top.name.len() != close_len or top.key != name_scan.key) return error.InvalidClosingTagName;
                    if (close_len > 8 and !std.mem.eql(u8, top.name.slice(input)[8..], input[name_start + 8 .. name_end])) return error.InvalidClosingTagName;
                }
                self.popStack();
                return i;
            }

            fn parsePiOrDeclaration(noalias self: *Self, input: []const u8, start: usize, ctx: anytype, comptime callback: anytype, comptime incremental: bool) ParseError!usize {
                var i = start + 2;
                if (i >= input.len) {
                    if (incremental) return error.UnexpectedEndOfData;
                    if (strict_mode) return error.ExpectedPiTarget;
                    return input.len;
                }
                if (!tables.isNameStart(input[i])) {
                    if (strict_mode) return error.ExpectedPiTarget;
                    const end0 = scanner.findSequence(input, i, "?>") orelse {
                        if (incremental) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    return end0 + 2;
                }

                const target_start = i;
                i = scanner.findNameEnd(input, i);
                const target_end = i;
                i = skipWs(input, i);
                const value_start = i;
                const end = scanner.findSequence(input, i, "?>") orelse {
                    if (strict_mode or incremental) return error.UnexpectedEndOfData;
                    return input.len;
                };
                if (include_misc_nodes) {
                    const decl = target_end - target_start == 3 and
                        ((input[target_start] | 0x20) == 'x') and
                        ((input[target_start + 1] | 0x20) == 'm') and
                        ((input[target_start + 2] | 0x20) == 'l');
                    const node: Node = .{
                        .source = input,
                        .kind = if (decl) .declaration else .pi,
                        .depth = @intCast(self.stackLen()),
                        .name = .{ .start = @intCast(target_start), .end = @intCast(target_end) },
                        .data = .{ .start = @intCast(value_start), .end = @intCast(end) },
                        .token_end = @intCast(end + 2),
                    };
                    _ = callCallback(ctx, callback, &node);
                }
                return end + 2;
            }

            fn parseBangNode(noalias self: *Self, input: []const u8, start: usize, ctx: anytype, comptime callback: anytype, comptime incremental: bool) ParseError!usize {
                if (start + 3 < input.len and input[start + 2] == '-' and input[start + 3] == '-') {
                    const value_start = start + 4;
                    const end = scanner.findSequence(input, value_start, "-->") orelse {
                        if (strict_mode or incremental) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    if (include_misc_nodes) {
                        const node: Node = .{
                            .source = input,
                            .kind = .comment,
                            .depth = @intCast(self.stackLen()),
                            .data = .{ .start = @intCast(value_start), .end = @intCast(end) },
                            .token_end = @intCast(end + 3),
                        };
                        _ = callCallback(ctx, callback, &node);
                    }
                    return end + 3;
                }
                if (start + 8 < input.len and input[start + 2] == '[' and input[start + 3] == 'C' and input[start + 4] == 'D' and input[start + 5] == 'A' and input[start + 6] == 'T' and input[start + 7] == 'A' and input[start + 8] == '[') {
                    const value_start = start + 9;
                    const end = scanner.findSequence(input, value_start, "]]>") orelse {
                        if (strict_mode or incremental) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    if (include_misc_nodes) {
                        const node: Node = .{
                            .source = input,
                            .kind = .cdata,
                            .depth = @intCast(self.stackLen()),
                            .data = .{ .start = @intCast(value_start), .end = @intCast(end) },
                            .token_end = @intCast(end + 3),
                        };
                        _ = callCallback(ctx, callback, &node);
                    }
                    return end + 3;
                }
                if (scanner.isDoctype(input, start)) {
                    const end = scanner.findDoctypeEnd(input, start + 9) orelse {
                        if (strict_mode or incremental) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    if (include_misc_nodes) {
                        const node: Node = .{
                            .source = input,
                            .kind = .doctype,
                            .depth = @intCast(self.stackLen()),
                            .data = .{ .start = @intCast(start + 9), .end = @intCast(end) },
                            .token_end = @intCast(end + 1),
                        };
                        _ = callCallback(ctx, callback, &node);
                    }
                    return end + 1;
                }
                if (incremental and bangPrefixNeedsMore(input, start)) return error.UnexpectedEndOfData;
                if (strict_mode) return error.ExpectedGt;
                const gt = scanner.findByte(input, start, '>') orelse {
                    if (incremental) return error.UnexpectedEndOfData;
                    return input.len;
                };
                return gt + 1;
            }

            const SkipProgress = struct {
                next: usize,
                needs_more: bool = false,
            };

            inline fn beginSkip(noalias self: *Self, root_name: Span, root_key: u64) ParseError!void {
                self.clearSkipStack();
                try self.pushSkip(root_name, root_key);
            }

            /// Walks a subtree without callbacks. The same token walker serves
            /// full parsing and cumulative-buffer incremental parsing; only EOF
            /// handling differs at comptime.
            fn walkSkipped(noalias self: *Self, input: []const u8, start: usize, comptime incremental: bool) ParseError!SkipProgress {
                var i = start;
                while (i < input.len) {
                    const lt = scanner.findByte(input, i, '<') orelse {
                        if (!incremental and require_closed_elements_on_eof) return error.UnexpectedEndOfData;
                        return .{ .next = input.len };
                    };
                    if (lt + 1 >= input.len) {
                        if (incremental) return .{ .next = lt, .needs_more = true };
                        if (strict_mode or require_closed_elements_on_eof) return error.UnexpectedEndOfData;
                        return .{ .next = input.len };
                    }

                    switch (input[lt + 1]) {
                        '/' => {
                            if (validate_closing_tags) {
                                const close = scanClosingTag(input, lt, strict_mode) catch |err| switch (err) {
                                    error.UnexpectedEndOfData => {
                                        if (incremental) return .{ .next = lt, .needs_more = true };
                                        if (strict_mode or require_closed_elements_on_eof) return err;
                                        return .{ .next = input.len };
                                    },
                                    else => return err,
                                };
                                const top = self.topSkip();
                                const close_len = close.name.len();
                                if (top.name.len() != close_len or top.key != close.key) return error.InvalidClosingTagName;
                                if (close_len > 8 and !std.mem.eql(u8, top.name.slice(input)[8..], close.name.slice(input)[8..])) return error.InvalidClosingTagName;
                                i = close.next;
                            } else {
                                const gt = scanner.findByte(input, lt + 2, '>') orelse {
                                    if (incremental) return .{ .next = lt, .needs_more = true };
                                    if (require_closed_elements_on_eof) return error.UnexpectedEndOfData;
                                    return .{ .next = input.len };
                                };
                                i = gt + 1;
                            }

                            self.popSkip();
                            if (self.skipStackLen() == 0) return .{ .next = i };
                        },
                        '?' => {
                            i = skipPi(input, lt, strict_mode, incremental) catch |err| switch (err) {
                                error.UnexpectedEndOfData => if (incremental)
                                    return .{ .next = lt, .needs_more = true }
                                else
                                    return err,
                                else => return err,
                            };
                        },
                        '!' => {
                            i = skipBang(input, lt, strict_mode, incremental) catch |err| switch (err) {
                                error.UnexpectedEndOfData => if (incremental)
                                    return .{ .next = lt, .needs_more = true }
                                else
                                    return err,
                                else => return err,
                            };
                        },
                        else => {
                            if (!tables.isNameStart(input[lt + 1])) {
                                if (strict_mode) return error.ExpectedElementName;
                                const gt = scanner.findByte(input, lt + 1, '>') orelse {
                                    if (incremental) return .{ .next = lt, .needs_more = true };
                                    return .{ .next = input.len };
                                };
                                i = gt + 1;
                                continue;
                            }

                            const open = scanOpeningTagToken(input, lt, strict_mode) catch |err| switch (err) {
                                error.UnexpectedEndOfData => if (incremental)
                                    return .{ .next = lt, .needs_more = true }
                                else
                                    return err,
                                else => return err,
                            };
                            i = open.next;
                            if (!open.self_closing) try self.pushSkip(open.name, open.key);
                        },
                    }
                }

                if (!incremental and require_closed_elements_on_eof) return error.UnexpectedEndOfData;
                return .{ .next = input.len };
            }

            inline fn skipSubtree(noalias self: *Self, input: []const u8, start: usize, root_name: Span, root_key: u64) ParseError!usize {
                try self.beginSkip(root_name, root_key);
                defer self.clearSkipStack();
                const progress = try self.walkSkipped(input, start, false);
                return progress.next;
            }

            fn tryFinishSimpleTextElement(
                noalias self: *Self,
                input: []const u8,
                content_start: usize,
                name: Span,
                name_key: u64,
                ctx: anytype,
                comptime callback: anytype,
            ) ParseError!?usize {
                if (content_start >= input.len or input[content_start] == '<') return null;

                const lt = scanner.findByte(input, content_start, '<') orelse return null;
                if (lt == content_start or lt + 2 >= input.len or input[lt + 1] != '/') return null;

                const open_len: usize = name.len();
                const close_start = lt + 2;
                const close_end = close_start + open_len;
                if (close_end > input.len) return null;
                if (scanner.prefixKey(input[close_start..close_end]) != name_key) return null;
                if (open_len > 8 and !std.mem.eql(u8, name.slice(input)[8..], input[close_start + 8 .. close_end])) return null;

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
                if (drop_whitespace_text_nodes and scanner.skipWhitespace(raw, 0) == raw.len) return j;

                const node: Node = .{
                    .source = input,
                    .kind = .text,
                    .depth = @intCast(self.stackLen() + 1),
                    .data = .{ .start = @intCast(content_start), .end = @intCast(lt) },
                    .token_end = @intCast(lt),
                };
                _ = callCallback(ctx, callback, &node);
                return j;
            }

            inline fn stackLen(self: *const Self) usize {
                return if (comptime validate_closing_tags) self.stack.items.len else self.stack;
            }

            inline fn skipStackLen(self: *const Self) usize {
                return if (comptime validate_closing_tags) self.skip_stack.items.len else self.skip_stack;
            }

            inline fn clearStacks(self: *Self) void {
                if (comptime validate_closing_tags) {
                    self.stack.items.len = 0;
                    self.skip_stack.items.len = 0;
                } else {
                    self.stack = 0;
                    self.skip_stack = 0;
                }
            }

            inline fn clearSkipStack(self: *Self) void {
                if (comptime validate_closing_tags) self.skip_stack.items.len = 0 else self.skip_stack = 0;
            }

            inline fn restoreStackLen(self: *Self, len: usize) void {
                if (comptime validate_closing_tags) self.stack.items.len = @min(len, self.stack.items.len) else self.stack = len;
            }

            inline fn restoreSkipStackLen(self: *Self, len: usize) void {
                if (comptime validate_closing_tags) self.skip_stack.items.len = @min(len, self.skip_stack.items.len) else self.skip_stack = len;
            }

            inline fn pushStack(noalias self: *Self, name: Span, key: u64) ParseError!void {
                if (comptime validate_closing_tags) {
                    const len = self.stack.items.len;
                    if (len == self.stack.capacity) self.stack.ensureTotalCapacityPrecise(self.allocator, len + len / 2 + 8) catch return error.OutOfMemory;
                    self.stack.appendAssumeCapacity(.{ .name = name, .key = key });
                } else {
                    self.stack += 1;
                }
            }

            inline fn popStack(self: *Self) void {
                if (comptime validate_closing_tags) self.stack.items.len -= 1 else self.stack -= 1;
            }

            inline fn topStack(self: *const Self) StackEntry {
                if (comptime !validate_closing_tags) unreachable;
                return self.stack.items[self.stack.items.len - 1];
            }

            inline fn pushSkip(noalias self: *Self, name: Span, key: u64) ParseError!void {
                if (comptime validate_closing_tags) {
                    try self.skip_stack.append(self.allocator, .{ .name = name, .key = key });
                } else {
                    self.skip_stack += 1;
                }
            }

            inline fn popSkip(self: *Self) void {
                if (comptime validate_closing_tags) self.skip_stack.items.len -= 1 else self.skip_stack -= 1;
            }

            inline fn topSkip(self: *const Self) StackEntry {
                if (comptime !validate_closing_tags) unreachable;
                return self.skip_stack.items[self.skip_stack.items.len - 1];
            }
        };
    };
}

const CallbackKind = enum {
    node,
    node_ptr,
    ctx_node,
    ctx_node_ptr,
};

fn callbackKind(comptime callback: anytype, comptime Node: type) CallbackKind {
    const cb_info = @typeInfo(@TypeOf(callback)).@"fn";
    return switch (cb_info.params.len) {
        1 => switch (cb_info.params[0].type.?) {
            Node => .node,
            *const Node => .node_ptr,
            else => @compileError("streaming callback node parameter must be Node or *const Node"),
        },
        2 => switch (cb_info.params[1].type.?) {
            Node => .ctx_node,
            *const Node => .ctx_node_ptr,
            else => @compileError("streaming callback node parameter must be Node or *const Node"),
        },
        else => @compileError("streaming callback must take (node), (*const node), (ctx, node), or (ctx, *const node) and return bool"),
    };
}

inline fn callCallback(ctx: anytype, comptime callback: anytype, node_ptr: anytype) bool {
    const Node = std.meta.Child(@TypeOf(node_ptr));
    return switch (comptime callbackKind(callback, Node)) {
        .node => callback(node_ptr.*),
        .node_ptr => callback(node_ptr),
        .ctx_node => callback(ctx, node_ptr.*),
        .ctx_node_ptr => callback(ctx, node_ptr),
    };
}

inline fn skipWs(input: []const u8, start: usize) usize {
    if (start >= input.len) return start;
    const c = input[start];
    if (c == ' ') {
        const next = start + 1;
        if (next >= input.len or input[next] != ' ') return next;
    } else if (!tables.isWhitespace(c)) {
        return start;
    }
    return scanner.skipWhitespace(input, start);
}

fn subtreeEndOffset(input: []const u8, kind: NodeType, token_end: IndexInt, self_closing: bool) ParseError!usize {
    const end: usize = token_end;
    return switch (kind) {
        .text, .comment, .cdata, .pi, .declaration, .doctype, .document => end,
        .element => if (self_closing) end else skipSubtreeStateless(input, end),
    };
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
                i = (try scanClosingTag(input, i, true)).next;
                depth -= 1;
                if (depth == 0) return i;
            },
            '?' => i = try skipPi(input, i, true, true),
            '!' => i = try skipBang(input, i, true, true),
            else => {
                const open = try scanOpeningTagToken(input, i, true);
                i = open.next;
                if (!open.self_closing) depth += 1;
            },
        }
    }
    return error.UnexpectedEndOfData;
}

const OpenToken = struct {
    next: usize,
    name: Span,
    key: u64,
    self_closing: bool,
};

const CloseToken = struct {
    next: usize,
    name: Span,
    key: u64,
};

fn scanOpeningTagToken(input: []const u8, start: usize, comptime strict: bool) ParseError!OpenToken {
    var i = start + 1;
    if (i >= input.len or !tables.isNameStart(input[i])) return error.ExpectedElementName;
    const name_start = i;
    const name_scan = scanner.scanNameAndKey(input, i);
    const name_end = name_scan.end;
    i = name_end;
    const name = Span{ .start = @intCast(name_start), .end = @intCast(name_end) };
    while (i < input.len) {
        const boundary = i;
        i = skipWs(input, i);
        if (i >= input.len) return error.UnexpectedEndOfData;
        const c = input[i];
        if (c == '>') return .{ .next = i + 1, .name = name, .key = name_scan.key, .self_closing = false };
        if (c == '/') {
            if (i + 1 >= input.len) return error.UnexpectedEndOfData;
            if (input[i + 1] == '>') return .{ .next = i + 2, .name = name, .key = name_scan.key, .self_closing = true };
        }
        if (strict and i == boundary) {
            @branchHint(.unlikely);
            return error.ExpectedAttributeName;
        }
        if (!tables.isNameStart(c)) {
            if (strict) return error.ExpectedAttributeName;
            i += 1;
            continue;
        }
        i = scanner.findNameEnd(input, i);
        i = skipWs(input, i);
        if (i >= input.len) return error.UnexpectedEndOfData;
        if (input[i] != '=') {
            if (strict) {
                @branchHint(.unlikely);
                return error.ExpectedEq;
            }
            continue;
        }
        i += 1;
        i = skipWs(input, i);
        if (i >= input.len) return error.UnexpectedEndOfData;
        const quote = input[i];
        if (quote == '\'' or quote == '"') {
            i = (scanner.findByte(input, i + 1, quote) orelse return error.UnexpectedEndOfData) + 1;
        } else {
            if (strict) return error.ExpectedQuote;
            const raw_end = scanner.findAttrUnquotedEnd(input, i);
            if (raw_end > i and raw_end < input.len and input[raw_end] == '>' and input[raw_end - 1] == '/') {
                i = raw_end - 1;
            } else {
                i = raw_end;
            }
        }
    }
    return error.UnexpectedEndOfData;
}

fn scanClosingTag(input: []const u8, start: usize, comptime strict: bool) ParseError!CloseToken {
    var i = start + 2;
    if (i < input.len and tables.isWhitespace(input[i])) {
        if (strict) return error.InvalidClosingTagName;
        i = skipWs(input, i);
    }
    if (i >= input.len) return error.UnexpectedEndOfData;
    if (!tables.isNameStart(input[i])) return error.InvalidClosingTagName;
    const name_start = i;
    const name_scan = scanner.scanNameAndKey(input, i);
    const name_end = name_scan.end;
    i = name_end;
    if (i < input.len and tables.isWhitespace(input[i])) i = skipWs(input, i);
    if (i >= input.len) return error.UnexpectedEndOfData;
    if (input[i] != '>') return error.InvalidClosingTagName;
    return .{ .next = i + 1, .name = .{ .start = @intCast(name_start), .end = @intCast(name_end) }, .key = name_scan.key };
}

fn skipPi(input: []const u8, start: usize, comptime strict: bool, comptime incremental: bool) ParseError!usize {
    const end = scanner.findSequence(input, start + 2, "?>") orelse {
        if (strict or incremental) return error.UnexpectedEndOfData;
        return input.len;
    };
    return end + 2;
}

fn tokenPrefixNeedsMore(input: []const u8, start: usize, comptime token: []const u8, comptime ascii_case_insensitive: bool) bool {
    if (start >= input.len) return false;
    const available = input.len - start;
    if (available >= token.len) return false;
    const prefix = token[0..available];
    if (ascii_case_insensitive) return std.ascii.eqlIgnoreCase(input[start..], prefix);
    return std.mem.eql(u8, input[start..], prefix);
}

fn bangPrefixNeedsMore(input: []const u8, start: usize) bool {
    return tokenPrefixNeedsMore(input, start, "<!--", false) or
        tokenPrefixNeedsMore(input, start, "<![CDATA[", false) or
        tokenPrefixNeedsMore(input, start, "<!DOCTYPE", true);
}

fn skipBang(input: []const u8, start: usize, comptime strict: bool, comptime incremental: bool) ParseError!usize {
    if (start + 3 < input.len and input[start + 2] == '-' and input[start + 3] == '-') {
        const end = scanner.findSequence(input, start + 4, "-->") orelse {
            if (strict or incremental) return error.UnexpectedEndOfData;
            return input.len;
        };
        return end + 3;
    }
    if (start + 8 < input.len and input[start + 2] == '[' and input[start + 3] == 'C' and input[start + 4] == 'D' and input[start + 5] == 'A' and input[start + 6] == 'T' and input[start + 7] == 'A' and input[start + 8] == '[') {
        const end = scanner.findSequence(input, start + 9, "]]>") orelse {
            if (strict or incremental) return error.UnexpectedEndOfData;
            return input.len;
        };
        return end + 3;
    }
    if (scanner.isDoctype(input, start)) {
        const end = scanner.findDoctypeEnd(input, start + 9) orelse {
            if (strict or incremental) return error.UnexpectedEndOfData;
            return input.len;
        };
        return end + 1;
    }
    if (incremental and bangPrefixNeedsMore(input, start)) return error.UnexpectedEndOfData;
    if (strict) return error.ExpectedGt;
    const gt = scanner.findByte(input, start + 2, '>') orelse {
        if (incremental) return error.UnexpectedEndOfData;
        return input.len;
    };
    return gt + 1;
}

test "streaming parser self-test: order attributes and depths" {
    const opts: ParseOptions = .{};
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        names: std.ArrayList([]const u8) = .empty,
        depths: std.ArrayList(IndexInt) = .empty,
        saw_attr: bool = false,

        fn onNode(self: *@This(), node: Event) bool {
            self.names.append(std.testing.allocator, node.nameSlice()) catch unreachable;
            self.depths.append(std.testing.allocator, node.depth) catch unreachable;
            if (node.kind == .element and std.mem.eql(u8, node.nameSlice(), "a")) {
                self.saw_attr = std.mem.eql(u8, node.getAttributeValueRaw("x").?, "y");
            }
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    defer ctx.names.deinit(std.testing.allocator);
    defer ctx.depths.deinit(std.testing.allocator);

    try parser.parse("<r><a x='y'>t</a><b/></r>", &ctx, Ctx.onNode);
    try std.testing.expectEqual(@as(usize, 4), ctx.names.items.len);
    try std.testing.expectEqualStrings("r", ctx.names.items[0]);
    try std.testing.expectEqualStrings("a", ctx.names.items[1]);
    try std.testing.expectEqualStrings("", ctx.names.items[2]);
    try std.testing.expectEqualStrings("b", ctx.names.items[3]);
    try std.testing.expectEqualSlices(IndexInt, &.{ 0, 1, 2, 1 }, ctx.depths.items);
    try std.testing.expect(ctx.saw_attr);
}

test "streaming parser self-test: skip validation and pointer callback" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        elements: usize = 0,
        saw_tail: bool = false,

        fn onNode(self: *@This(), node: *const Event) bool {
            if (node.kind == .element) self.elements += 1;
            if (node.kind == .element and std.mem.eql(u8, node.nameSlice(), "skip")) {
                self.saw_tail = std.mem.eql(u8, node.followingTextRaw() catch unreachable, "tail");
                return false;
            }
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try parser.parse("<r><skip><x/></skip>tail<keep>ok</keep></r>", &ctx, Ctx.onNode);
    try std.testing.expectEqual(@as(usize, 3), ctx.elements);
    try std.testing.expect(ctx.saw_tail);

    try std.testing.expectError(error.InvalidClosingTagName, parser.parse("<r><longername></r>", &ctx, Ctx.onNode));
}

test "streaming parser parseAvailable resumes from saved state" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        elements: usize = 0,
        text: usize = 0,

        fn onNode(self: *@This(), node: *const Event) bool {
            if (node.kind == .element) self.elements += 1;
            if (node.kind == .text) self.text += 1;
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expect(!try parser.parseAvailable("<r><item", &ctx, Ctx.onNode));
    try std.testing.expectEqual(@as(usize, 1), ctx.elements);
    const state = parser.save();

    parser.restore(state);
    try std.testing.expect(try parser.parseAvailable("<r><item>ok</item></r>", &ctx, Ctx.onNode));
    try parser.finish();
    try std.testing.expectEqual(@as(usize, 2), ctx.elements);
    try std.testing.expectEqual(@as(usize, 1), ctx.text);
}

test "streaming parseAvailable preserves whitespace when a later chunk extends text" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true, .drop_whitespace_text_nodes = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        elements: usize = 0,
        texts: usize = 0,
        saw_full_text: bool = false,

        fn onNode(self: *@This(), node: Event) bool {
            switch (node.kind) {
                .element => self.elements += 1,
                .text => {
                    self.texts += 1;
                    self.saw_full_text = std.mem.eql(u8, node.valueRawSlice(), "   x");
                },
                else => {},
            }
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expect(try parser.parseAvailable("<r>   ", &ctx, Ctx.onNode));
    try std.testing.expectEqual(@as(usize, 1), ctx.elements);
    try std.testing.expectEqual(@as(usize, 0), ctx.texts);

    try std.testing.expect(try parser.parseAvailable("<r>   x</r>", &ctx, Ctx.onNode));
    try parser.finish();
    try std.testing.expectEqual(@as(usize, 1), ctx.texts);
    try std.testing.expect(ctx.saw_full_text);
}

test "streaming parseAvailable accepts every valid token prefix" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true, .include_misc_nodes = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const source = "<?pi?><!DOCTYPE r [<!ELEMENT r ANY>]><r a='x'><!--c--><![CDATA[d]]><x/></r>";

    const Ctx = struct {
        events: usize = 0,
        fn onNode(self: *@This(), _: Event) bool {
            self.events += 1;
            return true;
        }
    };

    for (0..source.len + 1) |split| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};

        _ = try parser.parseAvailable(source[0..split], &ctx, Ctx.onNode);
        try std.testing.expect(try parser.parseAvailable(source, &ctx, Ctx.onNode));
        try parser.finish();
        try std.testing.expectEqual(@as(usize, 6), ctx.events);
    }
}

test "streaming skipped subtrees accept every valid token prefix" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const source = "<r><skip><?pi?><!----><![CDATA[x]]><a q='v'/></skip><tail/></r>";

    const Ctx = struct {
        elements: usize = 0,
        skip_callbacks: usize = 0,

        fn onNode(self: *@This(), node: Event) bool {
            if (node.kind != .element) return true;
            self.elements += 1;
            if (std.mem.eql(u8, node.nameSlice(), "skip")) {
                self.skip_callbacks += 1;
                return false;
            }
            return true;
        }
    };

    for (0..source.len + 1) |split| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};

        _ = try parser.parseAvailable(source[0..split], &ctx, Ctx.onNode);
        try std.testing.expect(try parser.parseAvailable(source, &ctx, Ctx.onNode));
        try parser.finish();
        try std.testing.expectEqual(@as(usize, 3), ctx.elements);
        try std.testing.expectEqual(@as(usize, 1), ctx.skip_callbacks);
    }
}

test "streaming strict token errors match DOM parsing" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const Document = document.Types(opts).Document;
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    const cases = [_][]const u8{
        "<r/>",
        "<r></r>",
        "<r a='x'/>",
        "<r a = 'x'/>",
        "<r a/>",
        "<r a='x'b='y'/>",
        "<r a='x>",
        "<r></ r>",
        "<r></x>",
        "<r>",
        "<?",
        "<?pi",
        "<!",
        "<!-",
        "<!--",
        "<!--x",
        "<![C",
        "<![CDATA[x",
        "<!D",
        "<!DOCTYPE r",
    };

    for (cases) |input| {
        var doc = Document.init(std.testing.allocator);
        defer doc.deinit();
        const dom_err: ?ParseError = blk: {
            doc.parse(input, opts) catch |err| break :blk err;
            break :blk null;
        };

        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        const stream_err: ?ParseError = blk: {
            parser.parse(input, &ctx, Ctx.onNode) catch |err| break :blk err;
            break :blk null;
        };

        if (dom_err != stream_err) std.debug.print("mismatch {s}: dom={any} stream={any}\n", .{ input, dom_err, stream_err });
        try std.testing.expectEqual(dom_err, stream_err);
    }
}

test "streaming strict start-tag grammar matches DOM strictness" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expectError(error.ExpectedEq, parser.parse("<r a/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.ExpectedAttributeName, parser.parse("<r !a='1'/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.ExpectedAttributeName, parser.parse("<r a='1'b='2'/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.ExpectedEq, parser.parse("<r a='1' b/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidClosingTagName, parser.parse("<r></ r>", &ctx, Ctx.onNode));
}

test "streaming parseAvailable does not replay callbacks across incomplete close tags" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true, .drop_whitespace_text_nodes = false };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        elements: usize = 0,
        texts: usize = 0,

        fn onNode(self: *@This(), node: Event) bool {
            if (node.kind == .element) self.elements += 1;
            if (node.kind == .text) self.texts += 1;
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expect(!try parser.parseAvailable("<r>text</r", &ctx, Ctx.onNode));
    try std.testing.expectEqual(@as(usize, 1), ctx.elements);
    try std.testing.expectEqual(@as(usize, 1), ctx.texts);
    try std.testing.expectError(error.UnexpectedEndOfData, parser.finish());

    try std.testing.expect(try parser.parseAvailable("<r>text</r>", &ctx, Ctx.onNode));
    try parser.finish();
    try std.testing.expectEqual(@as(usize, 1), ctx.elements);
    try std.testing.expectEqual(@as(usize, 1), ctx.texts);
}

test "streaming parseAvailable resumes skipped subtrees without replaying their root" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        elements: usize = 0,
        skip_callbacks: usize = 0,
        saw_tail: bool = false,

        fn onNode(self: *@This(), node: Event) bool {
            if (node.kind != .element) return true;
            self.elements += 1;
            if (std.mem.eql(u8, node.nameSlice(), "skip")) {
                self.skip_callbacks += 1;
                return false;
            }
            if (std.mem.eql(u8, node.nameSlice(), "tail")) self.saw_tail = true;
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expect(!try parser.parseAvailable("<r><skip><a", &ctx, Ctx.onNode));
    try std.testing.expectEqual(@as(usize, 2), ctx.elements);
    try std.testing.expectEqual(@as(usize, 1), ctx.skip_callbacks);

    try std.testing.expect(try parser.parseAvailable("<r><skip><a/></skip><tail/></r>", &ctx, Ctx.onNode));
    try parser.finish();
    try std.testing.expectEqual(@as(usize, 3), ctx.elements);
    try std.testing.expectEqual(@as(usize, 1), ctx.skip_callbacks);
    try std.testing.expect(ctx.saw_tail);
}

test "streaming skipped eof behavior matches normal descent" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = false };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        skip: bool,
        fn onNode(self: *@This(), node: Event) bool {
            return !(self.skip and node.kind == .element and std.mem.eql(u8, node.nameSlice(), "skip"));
        }
    };

    var descended = ParserType.init(std.testing.allocator);
    defer descended.deinit();
    var descend_ctx: Ctx = .{ .skip = false };
    try descended.parse("<skip><x/>", &descend_ctx, Ctx.onNode);

    var skipped = ParserType.init(std.testing.allocator);
    defer skipped.deinit();
    var skip_ctx: Ctx = .{ .skip = true };
    try skipped.parse("<skip><x/>", &skip_ctx, Ctx.onNode);
}

test "streaming require-closed does not accept a truncated close token" {
    const opts: ParseOptions = .{ .mode = .turbo, .validate_closing_tags = false, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    try std.testing.expectError(error.UnexpectedEndOfData, parser.parse("<r></", &ctx, Ctx.onNode));
}

test "streaming skipped subtrees honor require-closed at eof" {
    const opts: ParseOptions = .{ .mode = .turbo, .validate_closing_tags = false, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        fn onNode(_: *@This(), node: Event) bool {
            return !std.mem.eql(u8, node.nameSlice(), "skip");
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expectError(error.UnexpectedEndOfData, parser.parse("<skip><x/>", &ctx, Ctx.onNode));

    parser.clear();
    try std.testing.expect(try parser.parseAvailable("<skip><x/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.UnexpectedEndOfData, parser.finish());
}

test "streaming skipped subtrees remain strict-validated" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        fn onNode(_: *@This(), node: Event) bool {
            return !std.mem.eql(u8, node.nameSlice(), "skip");
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expectError(error.ExpectedQuote, parser.parse("<r><skip><x a=1/></skip></r>", &ctx, Ctx.onNode));

    parser.clear();
    try std.testing.expectError(error.ExpectedQuote, parser.parseAvailable("<r><skip><x a=1/></skip></r>", &ctx, Ctx.onNode));
}

test "streaming turbo parseAvailable waits for an incomplete closing token" {
    const opts: ParseOptions = .{ .mode = .turbo, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        elements: usize = 0,
        fn onNode(self: *@This(), node: Event) bool {
            if (node.kind == .element) self.elements += 1;
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expect(!try parser.parseAvailable("<r></r", &ctx, Ctx.onNode));
    try std.testing.expectEqual(@as(usize, 1), ctx.elements);
    try std.testing.expect(try parser.parseAvailable("<r></r>", &ctx, Ctx.onNode));
    try parser.finish();
    try std.testing.expectEqual(@as(usize, 1), ctx.elements);
}

test "streaming strict validation supports tag names longer than u16" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const name_len = 70_000;
    const source_len = name_len * 2 + 5;
    if (!common.lenFits(source_len)) return error.SkipZigTest;
    const source = try std.testing.allocator.alloc(u8, source_len);
    defer std.testing.allocator.free(source);

    source[0] = '<';
    @memset(source[1 .. 1 + name_len], 'a');
    source[1 + name_len] = '>';
    source[2 + name_len] = '<';
    source[3 + name_len] = '/';
    @memset(source[4 + name_len .. 4 + name_len * 2], 'a');
    source[source_len - 1] = '>';

    const Ctx = struct {
        count: usize = 0,
        fn onNode(self: *@This(), node: Event) bool {
            if (node.kind == .element) self.count += 1;
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    try parser.parse(source, &ctx, Ctx.onNode);
    try std.testing.expectEqual(@as(usize, 1), ctx.count);
}
