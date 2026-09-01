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
                while (i < self.input.len and !tables.isNameStart(self.input[i])) {
                    if (comptime options.mode == .strict) {
                        self.i = self.input.len;
                        return null;
                    }
                    i += 1;
                    i = scanner.skipWhitespace(self.input, i);
                }
                if (i >= self.input.len) {
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
                if (self.kind == .element or self.kind == .document) return "";
                return self.data.slice(self.source);
            }

            pub fn attributes(self: @This()) AttributeIterator {
                if (self.kind != .element) return .{ .input = "", .i = 0 };
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
                const end = try subtreeEndOffset(
                    self.source,
                    self.kind,
                    self.name,
                    self.token_end,
                    self.self_closing,
                    options.mode == .strict,
                    options.validate_closing_tags,
                );
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
        const Allocator = if (options.validate_closing_tags or options.mode == .strict) std.mem.Allocator else void;

        pub const Parser = struct {
            allocator: Allocator,
            stack: Stack = if (options.validate_closing_tags) .empty else 0,
            skip_stack: Stack = if (options.validate_closing_tags) .empty else 0,
            offset: usize = 0,
            needs_more: bool = false,
            state_tracking: bool = false,
            stack_generation: u64 = 0,
            restore_pending: bool = false,
            restore_stack_len: usize = 0,
            restore_skip_stack_len: usize = 0,
            restore_generation: u64 = 0,
            root_seen: bool = false,
            doctype_seen: bool = false,
            standalone_yes: bool = false,
            doctype_value_start: usize = 0,
            doctype_value_end: usize = 0,
            require_declared_entities: bool = true,
            xml_validated_offset: usize = 0,
            attribute_name_filter: u64 = 0,

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
                stack_generation: u64,
                root_seen: bool,
                doctype_seen: bool,
                standalone_yes: bool,
                doctype_value_start: usize,
                doctype_value_end: usize,
                require_declared_entities: bool,
            };

            const Checkpoint = struct {
                offset: usize,
                stack_len: usize,
                skip_stack_len: usize,
                needs_more: bool,
                root_seen: bool,
                doctype_seen: bool,
                standalone_yes: bool,
                doctype_value_start: usize,
                doctype_value_end: usize,
                require_declared_entities: bool,
            };

            pub fn init(allocator: std.mem.Allocator) Parser {
                return .{ .allocator = if (comptime validate_closing_tags or strict_mode) allocator else {} };
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
                self.root_seen = false;
                self.doctype_seen = false;
                self.standalone_yes = false;
                self.doctype_value_start = 0;
                self.doctype_value_end = 0;
                self.require_declared_entities = true;
                self.xml_validated_offset = 0;
                if (comptime strict_mode) {
                    try document.validateXmlCharacters(input);
                    self.xml_validated_offset = input.len;
                }
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
                        if (comptime strict_mode) {
                            const run = scanner.scanTextSpecials(input, i);
                            const has_non_whitespace = !tables.WhitespaceTable[input[i]] or scanner.skipWhitespace(input, i) < run.lt_index;
                            try self.validateCharacterDataSpecials(input, i, run.lt_index, run.has_close_bracket, run.has_ampersand, false);
                            if (self.stackLen() == 0 and has_non_whitespace) return error.InvalidDocumentContent;
                            if (run.lt_index > i and (!drop_whitespace_text_nodes or has_non_whitespace)) {
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
                        } else {
                            const lt_index = scanner.findByte(input, i, '<') orelse input.len;
                            const node: Node = .{
                                .source = input,
                                .kind = .text,
                                .depth = @intCast(self.stackLen()),
                                .data = .{ .start = @intCast(i), .end = @intCast(lt_index) },
                                .token_end = @intCast(lt_index),
                            };
                            _ = callCallback(ctx, callback, &node);
                            i = lt_index;
                        }
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
                if (comptime strict_mode) {
                    if (!self.root_seen) return error.ExpectedDocumentElement;
                }
                self.offset = i;
            }

            pub fn clear(self: *Self) void {
                self.clearStacks();
                self.offset = 0;
                self.needs_more = false;
                self.root_seen = false;
                self.doctype_seen = false;
                self.standalone_yes = false;
                self.doctype_value_start = 0;
                self.doctype_value_end = 0;
                self.require_declared_entities = true;
                self.xml_validated_offset = 0;
            }

            /// Saves the logical incremental-parser state. A saved state may be
            /// restored after parsing a different continuation of the same
            /// cumulative input prefix.
            pub fn save(self: *Self) State {
                self.state_tracking = true;
                return .{
                    .offset = self.offset,
                    .stack_len = self.stackLen(),
                    .skip_stack_len = self.skipStackLen(),
                    .needs_more = self.needs_more,
                    .stack_generation = if (self.restore_pending) self.restore_generation else self.stack_generation,
                    .root_seen = self.root_seen,
                    .doctype_seen = self.doctype_seen,
                    .standalone_yes = self.standalone_yes,
                    .doctype_value_start = self.doctype_value_start,
                    .doctype_value_end = self.doctype_value_end,
                    .require_declared_entities = self.require_declared_entities,
                };
            }

            /// Restores a state produced by `save`. Stack contents are rebuilt
            /// lazily from the cumulative input on the next `parseAvailable`
            /// call when the parser has taken a divergent branch since `save`.
            pub fn restore(self: *Self, state: State) void {
                self.offset = state.offset;
                self.needs_more = state.needs_more;
                self.root_seen = state.root_seen;
                self.doctype_seen = state.doctype_seen;
                self.standalone_yes = state.standalone_yes;
                self.doctype_value_start = state.doctype_value_start;
                self.doctype_value_end = state.doctype_value_end;
                self.require_declared_entities = state.require_declared_entities;
                // A restored continuation may diverge immediately after the
                // saved parse offset, so revalidate from that byte onward.
                self.xml_validated_offset = state.offset;
                self.state_tracking = true;

                if (comptime validate_closing_tags) {
                    if (!self.restore_pending and state.stack_generation == self.stack_generation) {
                        // No stack mutation happened since this state was saved.
                        std.debug.assert(state.stack_len == self.stack.items.len);
                        std.debug.assert(state.skip_stack_len == self.skip_stack.items.len);
                        return;
                    }
                    if (self.restore_pending and
                        state.stack_generation == self.restore_generation and
                        state.stack_len == self.restore_stack_len and
                        state.skip_stack_len == self.restore_skip_stack_len)
                    {
                        return;
                    }
                    self.restore_pending = true;
                    self.restore_stack_len = state.stack_len;
                    self.restore_skip_stack_len = state.skip_stack_len;
                    self.restore_generation = state.stack_generation;
                } else {
                    self.stack = state.stack_len;
                    self.skip_stack = state.skip_stack_len;
                }
            }

            inline fn checkpoint(self: *const Self) Checkpoint {
                return .{
                    .offset = self.offset,
                    .stack_len = self.stackLen(),
                    .skip_stack_len = self.skipStackLen(),
                    .needs_more = self.needs_more,
                    .root_seen = self.root_seen,
                    .doctype_seen = self.doctype_seen,
                    .standalone_yes = self.standalone_yes,
                    .doctype_value_start = self.doctype_value_start,
                    .doctype_value_end = self.doctype_value_end,
                    .require_declared_entities = self.require_declared_entities,
                };
            }

            inline fn restoreCheckpoint(self: *Self, state: Checkpoint) void {
                self.offset = state.offset;
                self.needs_more = state.needs_more;
                self.root_seen = state.root_seen;
                self.doctype_seen = state.doctype_seen;
                self.standalone_yes = state.standalone_yes;
                self.doctype_value_start = state.doctype_value_start;
                self.doctype_value_end = state.doctype_value_end;
                self.require_declared_entities = state.require_declared_entities;
                if (comptime validate_closing_tags) {
                    std.debug.assert(!self.restore_pending);
                    std.debug.assert(state.stack_len == self.stack.items.len);
                    std.debug.assert(state.skip_stack_len == self.skip_stack.items.len);
                } else {
                    self.stack = state.stack_len;
                    self.skip_stack = state.skip_stack_len;
                }
            }

            pub fn parseAvailable(noalias self: *Self, noalias input: []const u8, ctx: anytype, comptime callback: anytype) ParseError!bool {
                if (!common.lenFits(input.len)) return error.InputTooLarge;
                if (self.offset > input.len) return error.UnexpectedEndOfData;

                var parse_input = input;
                var trailing_partial_utf8 = false;
                if (comptime strict_mode) {
                    if (self.xml_validated_offset > input.len) return error.UnexpectedEndOfData;
                    const suffix = input[self.xml_validated_offset..];
                    const valid_suffix_len = try document.xmlValidPrefixLen(suffix);
                    self.xml_validated_offset += valid_suffix_len;
                    if (valid_suffix_len != suffix.len) {
                        trailing_partial_utf8 = true;
                        parse_input = input[0..self.xml_validated_offset];
                    }
                }

                try self.materializeRestoredStacks(parse_input);
                try self.reserveForInput(input.len);
                self.needs_more = false;

                while (self.offset < parse_input.len) {
                    if (self.skipStackLen() != 0) {
                        const progress = try self.walkSkipped(parse_input, self.offset, true);
                        self.offset = progress.next;
                        if (progress.needs_more) {
                            self.needs_more = true;
                            return false;
                        }
                        continue;
                    }
                    if (drop_whitespace_text_nodes and tables.WhitespaceTable[parse_input[self.offset]]) {
                        const next = scanner.skipWhitespace(parse_input, self.offset);
                        if (next >= parse_input.len) {
                            // Keep a trailing whitespace run pending: a later
                            // cumulative chunk may extend this same text node
                            // with non-whitespace bytes. `finish` may safely
                            // discard it when it really is the final run.
                            if (trailing_partial_utf8) {
                                self.needs_more = true;
                                return false;
                            }
                            return true;
                        }
                        if (parse_input[next] == '<') {
                            self.offset = next;
                            continue;
                        }
                    }
                    const saved = self.checkpoint();
                    const next = self.parseOne(parse_input, self.offset, ctx, callback, true) catch |err| switch (err) {
                        error.UnexpectedEndOfData => {
                            self.restoreCheckpoint(saved);
                            self.needs_more = true;
                            return false;
                        },
                        else => |e| return e,
                    };
                    self.offset = next;
                }
                if (trailing_partial_utf8) {
                    self.needs_more = true;
                    return false;
                }
                return true;
            }

            pub fn finish(self: *Self) ParseError!void {
                if (self.needs_more) return error.UnexpectedEndOfData;
                if (require_closed_elements_on_eof and (self.stackLen() != 0 or self.skipStackLen() != 0)) return error.UnexpectedEndOfData;
                if (comptime strict_mode) {
                    if (!self.root_seen) return error.ExpectedDocumentElement;
                }
            }

            inline fn parseOne(noalias self: *Self, input: []const u8, start: usize, ctx: anytype, comptime callback: anytype, comptime incremental: bool) ParseError!usize {
                const i = start;
                if (input[i] != '<') {
                    if (drop_whitespace_text_nodes and tables.WhitespaceTable[input[i]]) {
                        const next = scanner.skipWhitespace(input, i);
                        if (next >= input.len) return next;
                        if (input[next] == '<') return next;
                    }
                    if (comptime strict_mode) {
                        const run = scanner.scanTextSpecials(input, i);
                        const has_non_whitespace = !tables.WhitespaceTable[input[i]] or scanner.skipWhitespace(input, i) < run.lt_index;
                        try self.validateCharacterDataSpecials(input, i, run.lt_index, run.has_close_bracket, run.has_ampersand, incremental);
                        if (self.stackLen() == 0 and has_non_whitespace) return error.InvalidDocumentContent;
                        if (run.lt_index > i and (!drop_whitespace_text_nodes or has_non_whitespace)) {
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
                    const lt_index = scanner.findByte(input, i, '<') orelse input.len;
                    const node: Node = .{
                        .source = input,
                        .kind = .text,
                        .depth = @intCast(self.stackLen()),
                        .data = .{ .start = @intCast(i), .end = @intCast(lt_index) },
                        .token_end = @intCast(lt_index),
                    };
                    _ = callCallback(ctx, callback, &node);
                    return lt_index;
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

            inline fn doctypeValue(self: *const Self, input: []const u8) ?[]const u8 {
                if (!self.doctype_seen) return null;
                return input[self.doctype_value_start..self.doctype_value_end];
            }

            inline fn validateAttributeValue(self: *const Self, input: []const u8, value: []const u8) ParseError!void {
                const specials = scanner.bytePairPresence(value, '<', '&');
                if (specials.first) return error.InvalidAttributeValue;
                if (specials.second) {
                    try document.validateXmlAttributeReferencesAlloc(self.allocator, value, self.doctypeValue(input), self.require_declared_entities);
                }
            }

            inline fn validateCharacterDataSpecials(
                self: *const Self,
                input: []const u8,
                start: usize,
                end: usize,
                has_close_bracket: bool,
                has_ampersand: bool,
                comptime incremental: bool,
            ) ParseError!void {
                std.debug.assert(start <= end and end <= input.len);
                if (containsForbiddenCdataClose(input, start, end, has_close_bracket)) return error.InvalidCharacterData;
                if (has_ampersand) {
                    try document.validateXmlReferencesAlloc(self.allocator, input[start..end], incremental and end == input.len, self.doctypeValue(input), self.require_declared_entities);
                }
            }

            inline fn validateCharacterDataRange(self: *const Self, input: []const u8, start: usize, end: usize, comptime incremental: bool) ParseError!void {
                std.debug.assert(start <= end and end <= input.len);
                const specials = scanner.bytePairPresence(input[start..end], ']', '&');
                try self.validateCharacterDataSpecials(input, start, end, specials.first, specials.second, incremental);
            }

            inline fn reserveForInput(self: *Self, input_len: usize) !void {
                if (comptime validate_closing_tags) {
                    const est_stack = @max(@as(usize, 8), input_len / 512 +| 8);
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
                const name_scan = if (comptime validate_closing_tags)
                    scanner.scanNameAndKey(input, i)
                else if (comptime strict_mode) blk: {
                    const scan = scanner.scanNameEnd(input, i);
                    break :blk scanner.NameScan{
                        .end = scan.end,
                        .key = 0,
                        .needs_unicode_validation = scan.needs_unicode_validation,
                    };
                } else scanner.NameScan{ .end = scanner.findNameEnd(input, i), .key = 0 };
                const name_end = name_scan.end;
                if (comptime strict_mode) {
                    if (name_scan.needs_unicode_validation and !document.isValidXmlName(input[name_start..name_end])) return error.ExpectedElementName;
                }
                i = name_end;
                const name = Span{ .start = @intCast(name_start), .end = @intCast(name_end) };
                const attr_start = i;
                var attr_end = i;
                var attr_count: usize = 0;
                var first_attr_start: usize = 0;
                var first_attr_end: usize = 0;
                var self_closing = false;
                var closed = false;

                if (i < input.len and input[i] == '>') {
                    attr_end = i;
                    i += 1;
                    closed = true;
                } else if (i + 1 < input.len and input[i] == '/' and input[i + 1] == '>') {
                    attr_end = i;
                    i += 2;
                    self_closing = true;
                    closed = true;
                }

                while (!closed and i < input.len) {
                    const boundary = i;
                    i = skipWsMode(input, i, strict_mode);
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

                    const attr_name_start = i;
                    var attr_i: usize = undefined;
                    const attr_name_needs_unicode_validation = if (comptime strict_mode) blk: {
                        const scan = scanner.scanNameEnd(input, i);
                        attr_i = scan.end;
                        break :blk scan.needs_unicode_validation;
                    } else blk: {
                        attr_i = scanner.findNameEnd(input, i);
                        break :blk false;
                    };
                    if (comptime strict_mode) {
                        if (attr_name_needs_unicode_validation and !document.isValidXmlName(input[attr_name_start..attr_i])) return error.ExpectedAttributeName;
                        if (attr_count == 0) {
                            first_attr_start = attr_name_start;
                            first_attr_end = attr_i;
                        } else if (attr_count == 1) {
                            const first_len = first_attr_end - first_attr_start;
                            const current_len = attr_i - attr_name_start;
                            if (first_len == 1 and current_len == 1) {
                                if (input[first_attr_start] == input[attr_name_start]) {
                                    @branchHint(.unlikely);
                                    return error.DuplicateAttribute;
                                }
                                // Reversed bounds mark that the first two names are
                                // both one byte. Their exact starts are unnecessary
                                // once the direct duplicate check above has passed.
                                first_attr_start = attr_i;
                                first_attr_end = attr_name_start;
                            } else {
                                if (first_len == current_len and std.mem.eql(u8, input[first_attr_start..first_attr_end], input[attr_name_start..attr_i])) {
                                    @branchHint(.unlikely);
                                    return error.DuplicateAttribute;
                                }
                                first_attr_start = attr_name_start;
                                first_attr_end = attr_i;
                            }
                        } else {
                            if (attr_count == 2) self.attribute_name_filter = initAttributeNameFilter(input, attr_start, first_attr_start, first_attr_end);
                            addAttributeNameFilter(&self.attribute_name_filter, input[attr_name_start..attr_i]);
                        }
                        attr_count += 1;
                    }
                    if (attr_i + 1 < input.len and input[attr_i] == '=') {
                        const quote = input[attr_i + 1];
                        if (quote == '\'' or quote == '"') {
                            const quote_pos = scanner.findByte(input, attr_i + 2, quote) orelse {
                                if (incremental) return error.UnexpectedEndOfData;
                                if (strict_mode) return error.ExpectedQuote;
                                return error.UnexpectedEndOfData;
                            };
                            if (comptime strict_mode) try self.validateAttributeValue(input, input[attr_i + 2 .. quote_pos]);
                            i = quote_pos + 1;
                            continue;
                        }
                    }

                    attr_i = skipWsMode(input, attr_i, strict_mode);
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
                    attr_i = skipWsMode(input, attr_i, strict_mode);
                    if (attr_i >= input.len) return error.UnexpectedEndOfData;
                    const quote = input[attr_i];
                    if (quote == '\'' or quote == '"') {
                        const quote_pos = scanner.findByte(input, attr_i + 1, quote) orelse {
                            if (incremental) return error.UnexpectedEndOfData;
                            if (strict_mode) return error.ExpectedQuote;
                            return error.UnexpectedEndOfData;
                        };
                        if (comptime strict_mode) try self.validateAttributeValue(input, input[attr_i + 1 .. quote_pos]);
                        i = quote_pos + 1;
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
                if (comptime strict_mode) {
                    if (attr_count > 2 and self.attribute_name_filter & attribute_filter_collision != 0) {
                        try validateUniqueAttributesRaw(input, attr_start, attr_end);
                    }
                }

                if (comptime strict_mode) {
                    if (self.stackLen() == 0) {
                        if (self.root_seen) return error.MultipleDocumentElements;
                        self.root_seen = true;
                    }
                }

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
                if (comptime validate_closing_tags) {
                    if (!incremental) {
                        if (try self.tryFinishSimpleTextElement(input, i, name, name_scan.key, ctx, callback)) |next| return next;
                    }
                }

                try self.pushStack(name, name_scan.key);
                return i;
            }

            fn parseClosingTag(noalias self: *Self, input: []const u8, start: usize, comptime incremental: bool) ParseError!usize {
                if (!validate_closing_tags) {
                    if (comptime strict_mode) {
                        var i = start + 2;
                        if (i >= input.len) return error.UnexpectedEndOfData;
                        if (!tables.isNameStart(input[i])) return error.InvalidClosingTagName;
                        const close_name_start = i;
                        const close_scan = scanner.scanNameEndAfterStart(input, i);
                        i = close_scan.end;
                        if (close_scan.needs_unicode_validation and !document.isValidXmlName(input[close_name_start..i])) return error.InvalidClosingTagName;
                        if (i < input.len and tables.isWhitespace(input[i])) i = skipWsMode(input, i, true);
                        if (i >= input.len) return error.UnexpectedEndOfData;
                        if (input[i] != '>') return error.InvalidClosingTagName;
                        if (self.stackLen() != 0) self.popStack();
                        return i + 1;
                    }
                    const gt = scanner.findByte(input, start + 2, '>') orelse {
                        if (incremental) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    if (self.stackLen() != 0) self.popStack();
                    return gt + 1;
                }

                var i = start + 2;
                if (i < input.len and tables.isWhitespace(input[i])) {
                    @branchHint(.unlikely);
                    if (strict_mode) return error.InvalidClosingTagName;
                    i = skipWsMode(input, i, strict_mode);
                }
                if (i >= input.len) {
                    if (strict_mode or incremental) return error.UnexpectedEndOfData;
                    return input.len;
                }
                if (self.stackLen() == 0) {
                    @branchHint(.unlikely);
                    return error.InvalidClosingTagName;
                }
                if (!tables.isNameStart(input[i])) {
                    @branchHint(.unlikely);
                    if (validate_closing_tags) return error.InvalidClosingTagName;
                    const gt = scanner.findByte(input, i, '>') orelse input.len;
                    return if (gt < input.len) gt + 1 else gt;
                }
                const name_start = i;
                const name_scan = scanner.scanNameAndKeyAfterStart(input, i);
                const name_end = name_scan.end;
                // With closing-tag validation enabled, an exact match against the
                // already validated opening name proves XML Name validity too.
                i = name_end;
                if (i < input.len and tables.isWhitespace(input[i])) {
                    @branchHint(.unlikely);
                    i = skipWsMode(input, i, strict_mode);
                }
                if (i >= input.len) {
                    if (strict_mode or incremental) return error.UnexpectedEndOfData;
                    return error.InvalidClosingTagName;
                }
                if (input[i] != '>') {
                    @branchHint(.unlikely);
                    return error.InvalidClosingTagName;
                }
                i += 1;

                if (validate_closing_tags) {
                    const top = self.topStack();
                    const close_len = name_end - name_start;
                    if (top.name.len() != close_len or top.key != name_scan.key) {
                        @branchHint(.unlikely);
                        return error.InvalidClosingTagName;
                    }
                    if (close_len > 8 and !std.mem.eql(u8, top.name.slice(input)[8..], input[name_start + 8 .. name_end])) {
                        @branchHint(.unlikely);
                        return error.InvalidClosingTagName;
                    }
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
                const target_needs_unicode_validation = if (comptime strict_mode) blk: {
                    const scan = scanner.scanNameEnd(input, i);
                    i = scan.end;
                    break :blk scan.needs_unicode_validation;
                } else blk: {
                    i = scanner.findNameEnd(input, i);
                    break :blk false;
                };
                const target_end = i;
                if (comptime strict_mode) {
                    if (target_needs_unicode_validation and !document.isValidXmlName(input[target_start..target_end])) return error.ExpectedPiTarget;
                }
                const xml_target = target_end - target_start == 3 and std.ascii.eqlIgnoreCase(input[target_start..target_end], "xml");
                if (comptime strict_mode) {
                    if (xml_target and !std.mem.eql(u8, input[target_start..target_end], "xml")) return error.ExpectedPiTarget;
                    if (xml_target and start != 0) return error.InvalidDeclaration;
                    if (xml_target and (target_end >= input.len or !tables.isWhitespace(input[target_end]))) return error.InvalidDeclaration;
                    if (!xml_target) {
                        if (target_end >= input.len) return error.UnexpectedEndOfData;
                        if (!tables.isWhitespace(input[target_end])) {
                            if (input[target_end] != '?') return error.ExpectedGt;
                            if (target_end + 1 >= input.len) return error.UnexpectedEndOfData;
                            if (input[target_end + 1] != '>') return error.ExpectedGt;
                        }
                    }
                }
                i = skipWsMode(input, i, strict_mode);
                const value_start = i;
                const end = scanner.findSequence(input, i, "?>") orelse {
                    if (strict_mode or incremental) return error.UnexpectedEndOfData;
                    return input.len;
                };
                if (comptime strict_mode) {
                    if (xml_target) {
                        const declaration = try document.validateXmlDeclaration(input[value_start..end]);
                        self.standalone_yes = declaration.standalone_yes;
                    }
                }
                if (include_misc_nodes) {
                    const decl = xml_target;
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
                    if (comptime strict_mode) try validateComment(input[value_start..end]);
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
                    if (comptime strict_mode) {
                        if (self.stackLen() == 0) return error.InvalidDocumentContent;
                    }
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
                    if (comptime strict_mode) {
                        if (!scanner.isDoctypeExact(input, start)) return error.ExpectedGt;
                        if (self.stackLen() != 0 or self.root_seen or self.doctype_seen) return error.InvalidDoctype;
                    }
                    const end = scanner.findDoctypeEnd(input, start + 9) orelse {
                        if (strict_mode or incremental) return error.UnexpectedEndOfData;
                        return input.len;
                    };
                    if (comptime strict_mode) {
                        const value_start = start + 9;
                        const info = try document.validateDoctypeAlloc(self.allocator, input[value_start..end]);
                        self.doctype_value_start = value_start;
                        self.doctype_value_end = end;
                        self.require_declared_entities = self.standalone_yes or (!info.has_external_id and !info.has_parameter_entity_references);
                        try document.validateDoctypeEntityConstraintsAlloc(
                            self.allocator,
                            input[value_start..end],
                            self.require_declared_entities,
                        );
                        self.doctype_seen = true;
                    }
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
                    var text_scan: scanner.TextSpecialRun = undefined;
                    const lt = if (comptime strict_mode) blk: {
                        text_scan = scanner.scanTextSpecials(input, i);
                        break :blk text_scan.lt_index;
                    } else scanner.findByte(input, i, '<') orelse input.len;
                    if (comptime strict_mode) {
                        self.validateCharacterDataSpecials(input, i, lt, text_scan.has_close_bracket, text_scan.has_ampersand, incremental) catch |err| switch (err) {
                            error.UnexpectedEndOfData => if (incremental) return .{ .next = i, .needs_more = true } else return err,
                            else => return err,
                        };
                    }
                    if (lt == input.len) {
                        if (!incremental and require_closed_elements_on_eof) return error.UnexpectedEndOfData;
                        return .{ .next = input.len };
                    }
                    if (lt + 1 >= input.len) {
                        if (incremental) return .{ .next = lt, .needs_more = true };
                        if (strict_mode or require_closed_elements_on_eof) return error.UnexpectedEndOfData;
                        return .{ .next = input.len };
                    }

                    switch (input[lt + 1]) {
                        '/' => {
                            if (comptime strict_mode or validate_closing_tags) {
                                const close = scanClosingTag(input, lt, strict_mode, incremental) catch |err| switch (err) {
                                    error.UnexpectedEndOfData => {
                                        if (incremental) return .{ .next = lt, .needs_more = true };
                                        if (strict_mode or require_closed_elements_on_eof) return err;
                                        return .{ .next = input.len };
                                    },
                                    else => return err,
                                };
                                if (comptime validate_closing_tags) {
                                    const top = self.topSkip();
                                    const close_len = close.name.len();
                                    if (top.name.len() != close_len or top.key != close.key) return error.InvalidClosingTagName;
                                    if (close_len > 8 and !std.mem.eql(u8, top.name.slice(input)[8..], close.name.slice(input)[8..])) return error.InvalidClosingTagName;
                                }
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
                            if (comptime strict_mode) {
                                if (scanner.isDoctype(input, lt)) return error.InvalidDoctype;
                            }
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
                                    if (require_closed_elements_on_eof) return error.UnexpectedEndOfData;
                                    return .{ .next = input.len };
                                };
                                i = gt + 1;
                                continue;
                            }

                            const open = scanOpeningTagToken(input, lt, strict_mode, if (comptime strict_mode) self.allocator else null, self.doctypeValue(input), self.require_declared_entities) catch |err| switch (err) {
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

                var text_scan: scanner.TextSpecialRun = undefined;
                const lt = if (comptime strict_mode) blk: {
                    text_scan = scanner.scanTextSpecials(input, content_start);
                    break :blk text_scan.lt_index;
                } else scanner.findByte(input, content_start, '<') orelse return null;
                if (lt >= input.len) return null;
                if (lt + 2 >= input.len or input[lt + 1] != '/') return null;

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
                    j = skipWsMode(input, j, strict_mode);
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
                if (comptime strict_mode) {
                    try self.validateCharacterDataSpecials(input, content_start, lt, text_scan.has_close_bracket, text_scan.has_ampersand, false);
                }
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

            fn materializeRestoredStacks(self: *Self, input: []const u8) ParseError!void {
                if (comptime !validate_closing_tags) return;
                if (!self.restore_pending) return;

                const expected_main = self.restore_stack_len;
                const expected_skip = self.restore_skip_stack_len;
                const expected_total = std.math.add(usize, expected_main, expected_skip) catch return error.InputTooLarge;

                const RebuildCtx = struct {
                    fn onNode(_: *@This(), _: *const Node) bool {
                        return true;
                    }
                };

                var rebuilt = Self.init(self.allocator);
                defer rebuilt.deinit();
                var rebuild_ctx: RebuildCtx = .{};
                _ = try rebuilt.parseAvailable(input[0..self.offset], &rebuild_ctx, RebuildCtx.onNode);

                if (rebuilt.stack.items.len != expected_total or rebuilt.skip_stack.items.len != 0) {
                    return error.InvalidClosingTagName;
                }

                try self.stack.ensureTotalCapacity(self.allocator, expected_main);
                try self.skip_stack.ensureTotalCapacity(self.allocator, expected_skip);
                self.stack.items.len = 0;
                self.skip_stack.items.len = 0;
                self.stack.appendSliceAssumeCapacity(rebuilt.stack.items[0..expected_main]);
                self.skip_stack.appendSliceAssumeCapacity(rebuilt.stack.items[expected_main..expected_total]);
                self.restore_pending = false;
                self.noteStackMutation();
            }

            inline fn stackLen(self: *const Self) usize {
                if (comptime validate_closing_tags) {
                    return if (self.restore_pending) self.restore_stack_len else self.stack.items.len;
                }
                return self.stack;
            }

            inline fn skipStackLen(self: *const Self) usize {
                if (comptime validate_closing_tags) {
                    return if (self.restore_pending) self.restore_skip_stack_len else self.skip_stack.items.len;
                }
                return self.skip_stack;
            }

            inline fn noteStackMutation(self: *Self) void {
                if (comptime validate_closing_tags) {
                    if (self.state_tracking) self.stack_generation +%= 1;
                }
            }

            inline fn clearStacks(self: *Self) void {
                if (comptime validate_closing_tags) {
                    if (self.stack.items.len != 0 or self.skip_stack.items.len != 0 or self.restore_pending) self.noteStackMutation();
                    self.stack.items.len = 0;
                    self.skip_stack.items.len = 0;
                    self.restore_pending = false;
                } else {
                    self.stack = 0;
                    self.skip_stack = 0;
                }
            }

            inline fn clearSkipStack(self: *Self) void {
                if (comptime validate_closing_tags) {
                    if (self.skip_stack.items.len != 0) self.noteStackMutation();
                    self.skip_stack.items.len = 0;
                } else self.skip_stack = 0;
            }

            inline fn pushStack(noalias self: *Self, name: Span, key: u64) ParseError!void {
                if (comptime validate_closing_tags) {
                    const len = self.stack.items.len;
                    if (len == self.stack.capacity) self.stack.ensureTotalCapacityPrecise(self.allocator, len +| len / 2 +| 8) catch return error.OutOfMemory;
                    self.stack.appendAssumeCapacity(.{ .name = name, .key = key });
                    self.noteStackMutation();
                } else {
                    self.stack += 1;
                }
            }

            inline fn popStack(self: *Self) void {
                if (comptime validate_closing_tags) {
                    self.stack.items.len -= 1;
                    self.noteStackMutation();
                } else self.stack -= 1;
            }

            inline fn topStack(self: *const Self) StackEntry {
                if (comptime !validate_closing_tags) unreachable;
                return self.stack.items[self.stack.items.len - 1];
            }

            inline fn pushSkip(noalias self: *Self, name: Span, key: u64) ParseError!void {
                if (comptime validate_closing_tags) {
                    try self.skip_stack.append(self.allocator, .{ .name = name, .key = key });
                    self.noteStackMutation();
                } else {
                    self.skip_stack += 1;
                }
            }

            inline fn popSkip(self: *Self) void {
                if (comptime validate_closing_tags) {
                    self.skip_stack.items.len -= 1;
                    self.noteStackMutation();
                } else self.skip_stack -= 1;
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
        if (next >= input.len or !tables.isWhitespace(input[next])) return next;
    } else if (!tables.isWhitespace(c)) {
        return start;
    }
    return scanner.skipWhitespace(input, start);
}

inline fn skipWsStrict(input: []const u8, start: usize) usize {
    if (start >= input.len) return start;
    const c = input[start];
    if (c == ' ') {
        const next = start + 1;
        // XML whitespace is limited to space, tab, LF, and CR. Every one of
        // those bytes is <= ASCII space, so ordinary ` space + token` input
        // exits here while mixed whitespace falls through to the full scan.
        if (next >= input.len or input[next] > ' ') return next;
    } else if (!tables.isWhitespace(c)) {
        return start;
    }
    return scanner.skipWhitespace(input, start);
}

inline fn skipWsMode(input: []const u8, start: usize, comptime strict: bool) usize {
    if (comptime strict) return skipWsStrict(input, start);
    return skipWs(input, start);
}

fn subtreeEndOffset(
    input: []const u8,
    kind: NodeType,
    name: Span,
    token_end: IndexInt,
    self_closing: bool,
    comptime strict: bool,
    comptime validate_closing_tags: bool,
) ParseError!usize {
    const end: usize = token_end;
    return switch (kind) {
        .text, .comment, .cdata, .pi, .declaration, .doctype, .document => end,
        .element => if (self_closing)
            end
        else
            skipSubtreeStateless(input, end, name, strict, validate_closing_tags),
    };
}

fn skipSubtreeStateless(
    input: []const u8,
    start: usize,
    root_name: Span,
    comptime strict: bool,
    comptime validate_closing_tags: bool,
) ParseError!usize {
    var depth: usize = 1;
    var i = start;
    while (i < input.len) {
        var text_scan: scanner.TextSpecialRun = undefined;
        const lt = if (comptime strict) blk: {
            text_scan = scanner.scanTextSpecials(input, i);
            break :blk text_scan.lt_index;
        } else scanner.findByte(input, i, '<') orelse input.len;
        if (comptime strict) {
            try validateCharacterDataSpecials(input, i, lt, text_scan.has_close_bracket, text_scan.has_ampersand, false);
        }
        if (lt == input.len) return error.UnexpectedEndOfData;
        i = lt;
        if (i + 1 >= input.len) return error.UnexpectedEndOfData;
        switch (input[i + 1]) {
            '/' => {
                if (comptime strict or validate_closing_tags) {
                    const close = try scanClosingTag(input, i, strict, false);
                    if (comptime validate_closing_tags) {
                        const expected = try expectedOpenNameAtDepth(input, start, root_name, i, depth, strict);
                        const close_len = close.name.len();
                        if (expected.len() != close_len or scanner.prefixKey(expected.slice(input)) != close.key) {
                            return error.InvalidClosingTagName;
                        }
                        if (close_len > 8 and !std.mem.eql(u8, expected.slice(input)[8..], close.name.slice(input)[8..])) {
                            return error.InvalidClosingTagName;
                        }
                    }
                    i = close.next;
                } else {
                    const gt = scanner.findByte(input, i + 2, '>') orelse return error.UnexpectedEndOfData;
                    i = gt + 1;
                }
                if (depth == 0) return error.InvalidClosingTagName;
                depth -= 1;
                if (depth == 0) return i;
            },
            '?' => i = try skipPi(input, i, strict, true),
            '!' => i = try skipBang(input, i, strict, true),
            else => {
                if (!tables.isNameStart(input[i + 1])) {
                    if (comptime strict) return error.ExpectedElementName;
                    const gt = scanner.findByte(input, i + 1, '>') orelse return error.UnexpectedEndOfData;
                    i = gt + 1;
                    continue;
                }
                const open = try scanOpeningTagToken(input, i, strict, null, null, false);
                i = open.next;
                if (!open.self_closing) depth += 1;
            },
        }
    }
    return error.UnexpectedEndOfData;
}

fn expectedOpenNameAtDepth(
    input: []const u8,
    start: usize,
    root_name: Span,
    before: usize,
    target_depth: usize,
    comptime strict: bool,
) ParseError!Span {
    if (target_depth == 0) return error.InvalidClosingTagName;
    var depth: usize = 1;
    var candidate = root_name;
    var i = start;
    while (i < before) {
        const lt = scanner.findByte(input, i, '<') orelse break;
        if (lt >= before or lt + 1 >= input.len) break;
        i = lt;
        switch (input[i + 1]) {
            '/' => {
                if (comptime strict) {
                    i = (try scanClosingTag(input, i, true, false)).next;
                } else {
                    const gt = scanner.findByte(input, i + 2, '>') orelse return error.UnexpectedEndOfData;
                    i = gt + 1;
                }
                if (depth == 0) return error.InvalidClosingTagName;
                depth -= 1;
            },
            '?' => i = try skipPi(input, i, strict, true),
            '!' => i = try skipBang(input, i, strict, true),
            else => {
                if (!tables.isNameStart(input[i + 1])) {
                    if (comptime strict) return error.ExpectedElementName;
                    const gt = scanner.findByte(input, i + 1, '>') orelse return error.UnexpectedEndOfData;
                    i = gt + 1;
                    continue;
                }
                const open = try scanOpeningTagToken(input, i, strict, null, null, false);
                i = open.next;
                if (!open.self_closing) {
                    depth += 1;
                    if (depth == target_depth) candidate = open.name;
                }
            },
        }
    }
    if (depth != target_depth) return error.InvalidClosingTagName;
    return candidate;
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

fn scanOpeningTagToken(input: []const u8, start: usize, comptime strict: bool, entity_allocator: ?std.mem.Allocator, doctype_value: ?[]const u8, require_declared_entities: bool) ParseError!OpenToken {
    var i = start + 1;
    if (i >= input.len or !tables.isNameStart(input[i])) return error.ExpectedElementName;
    const name_start = i;
    const name_scan = scanner.scanNameAndKey(input, i);
    const name_end = name_scan.end;
    if (comptime strict) {
        if (name_scan.needs_unicode_validation and !document.isValidXmlName(input[name_start..name_end])) return error.ExpectedElementName;
    }
    i = name_end;
    const name = Span{ .start = @intCast(name_start), .end = @intCast(name_end) };
    var attr_count: usize = 0;
    var first_attr_start: usize = 0;
    var first_attr_end: usize = 0;
    while (i < input.len) {
        const boundary = i;
        i = skipWsMode(input, i, strict);
        if (i >= input.len) return error.UnexpectedEndOfData;
        const c = input[i];
        if (c == '>') {
            if (comptime strict) {
                if (attr_count > 2) try validateUniqueAttributesRaw(input, name_end, i);
            }
            return .{ .next = i + 1, .name = name, .key = name_scan.key, .self_closing = false };
        }
        if (c == '/') {
            if (i + 1 >= input.len) return error.UnexpectedEndOfData;
            if (input[i + 1] == '>') {
                if (comptime strict) {
                    if (attr_count > 2) try validateUniqueAttributesRaw(input, name_end, i);
                }
                return .{ .next = i + 2, .name = name, .key = name_scan.key, .self_closing = true };
            }
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
        if (comptime strict) {
            const attr_name_start = i;
            const attr_name_scan = scanner.scanNameEnd(input, i);
            i = attr_name_scan.end;
            if (attr_name_scan.needs_unicode_validation and !document.isValidXmlName(input[attr_name_start..i])) return error.ExpectedAttributeName;
            if (attr_count == 0) {
                first_attr_start = attr_name_start;
                first_attr_end = i;
            } else if (attr_count == 1) {
                const first_len = first_attr_end - first_attr_start;
                const current_len = i - attr_name_start;
                if (first_len == current_len and std.mem.eql(u8, input[first_attr_start..first_attr_end], input[attr_name_start..i])) {
                    @branchHint(.unlikely);
                    return error.DuplicateAttribute;
                }
            }
            attr_count += 1;
        } else {
            i = scanner.findNameEnd(input, i);
        }
        i = skipWsMode(input, i, strict);
        if (i >= input.len) return error.UnexpectedEndOfData;
        if (input[i] != '=') {
            if (strict) {
                @branchHint(.unlikely);
                return error.ExpectedEq;
            }
            continue;
        }
        i += 1;
        i = skipWsMode(input, i, strict);
        if (i >= input.len) return error.UnexpectedEndOfData;
        const quote = input[i];
        if (quote == '\'' or quote == '"') {
            const quote_pos = scanner.findByte(input, i + 1, quote) orelse return error.UnexpectedEndOfData;
            if (comptime strict) {
                const value = input[i + 1 .. quote_pos];
                const specials = scanner.bytePairPresence(value, '<', '&');
                if (specials.first) return error.InvalidAttributeValue;
                if (specials.second) {
                    if (entity_allocator) |allocator| {
                        try document.validateXmlAttributeReferencesAlloc(allocator, value, doctype_value, require_declared_entities);
                    } else {
                        try document.validateXmlAttributeReferences(value, doctype_value, require_declared_entities);
                    }
                }
            }
            i = quote_pos + 1;
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

const ValidatedAttrToken = struct {
    name_start: usize,
    name_end: usize,
    next: usize,
};

fn scanValidatedAttributeToken(input: []const u8, start: usize, end: usize) ParseError!?ValidatedAttrToken {
    var i = start;
    if (i >= end) return null;

    // This is a second, duplicate-name-only pass over an already validated
    // opening tag. Optimize the overwhelmingly common ` name='value'` shape:
    // one ASCII space before the name and no whitespace around `=`. Fall back
    // to the strict whitespace scanner only for mixed/long whitespace.
    if (input[i] == ' ') {
        i += 1;
        if (i >= end) return null;
        if (input[i] <= ' ') i = skipWsStrict(input, i);
    } else if (tables.isWhitespace(input[i])) {
        i = skipWsStrict(input, i);
    }
    if (i >= end) return null;

    // The opening-tag scanner has already validated the complete attribute
    // grammar, XML Name, and value references. This pass exists only to find
    // duplicate names, so do not repeat that work.
    if (!tables.isNameStart(input[i])) return error.ExpectedAttributeName;
    const name_start = i;
    i = scanner.findNameEndAfterStart(input, i);
    const name_end = i;

    if (i >= end or input[i] != '=') {
        i = skipWsStrict(input, i);
        if (i >= end or input[i] != '=') return error.ExpectedEq;
    }
    i += 1;
    if (i >= end) return error.ExpectedQuote;
    var quote = input[i];
    if (quote != '\'' and quote != '"') {
        i = skipWsStrict(input, i);
        if (i >= end) return error.ExpectedQuote;
        quote = input[i];
        if (quote != '\'' and quote != '"') return error.ExpectedQuote;
    }
    const quote_pos = scanner.findByte(input[0..end], i + 1, quote) orelse unreachable;
    return .{ .name_start = name_start, .name_end = name_end, .next = quote_pos + 1 };
}

fn scanValidatedAttributeTokenLarge(input: []const u8, start: usize, end: usize) ParseError!?ValidatedAttrToken {
    if (start >= end) return null;
    if (input[start] == ' ' and start + 4 < end) {
        const name_start = start + 1;
        var name_end: usize = undefined;
        if (input[name_start + 1] == '=') {
            name_end = name_start + 1;
        } else if (name_start + 2 < end and input[name_start + 2] == '=') {
            name_end = name_start + 2;
        } else if (name_start + 3 < end and input[name_start + 3] == '=') {
            name_end = name_start + 3;
        } else {
            return scanValidatedAttributeToken(input, start, end);
        }
        const quote = input[name_end + 1];
        if (quote == '\'' or quote == '"') {
            const quote_pos = scanner.findByte(input[0..end], name_end + 2, quote) orelse unreachable;
            return .{ .name_start = name_start, .name_end = name_end, .next = quote_pos + 1 };
        }
    }
    return scanValidatedAttributeToken(input, start, end);
}

const attribute_filter_collision = @as(u64, 1) << 63;

inline fn addAttributeNameFilter(filter: *u64, name: []const u8) void {
    if (name.len == 1) {
        addAttributeNameFilterBucket(filter, oneByteAttributeNameBucket(name[0]));
        return;
    }
    const hash = attributeNameHash(name);
    var bucket: u6 = @intCast(hash >> 58);
    if (bucket == 63) bucket = 62;
    addAttributeNameFilterBucket(filter, bucket);
}

inline fn oneByteAttributeNameBucket(c: u8) u6 {
    // Strict one-byte XML names are ASCII NameStart bytes. Their low six bits
    // are unique except ':' and 'z'; bucket zero is otherwise unused.
    return if (c == ':') 0 else @intCast(c & 63);
}

inline fn addAttributeNameFilterBucket(filter: *u64, bucket: u6) void {
    const bit = @as(u64, 1) << bucket;
    if (filter.* & bit != 0) filter.* |= attribute_filter_collision;
    filter.* |= bit;
}

noinline fn initAttributeNameFilter(input: []const u8, start: usize, second_start: usize, second_end: usize) u64 {
    var filter: u64 = 0;
    const first_start = skipWsStrict(input, start);
    if (second_start > second_end) {
        const first_bucket = oneByteAttributeNameBucket(input[first_start]);
        const second_bucket = oneByteAttributeNameBucket(input[second_end]);
        return (@as(u64, 1) << first_bucket) | (@as(u64, 1) << second_bucket);
    }
    const first = scanner.scanNameAndKeyAfterStart(input, first_start);
    addAttributeNameFilterKey(&filter, first.key, first.end - first_start);
    addAttributeNameFilter(&filter, input[second_start..second_end]);
    return filter;
}

inline fn addAttributeNameFilterKey(filter: *u64, key: u64, name_len: usize) void {
    if (name_len == 1) {
        addAttributeNameFilterBucket(filter, oneByteAttributeNameBucket(@truncate(key)));
        return;
    }
    var mixed = key ^ (@as(u64, name_len) << 56);
    mixed *%= 0x9e3779b97f4a7c15;
    mixed ^= mixed >> 32;
    var bucket: u6 = @intCast(mixed >> 58);
    if (bucket == 63) bucket = 62;
    addAttributeNameFilterBucket(filter, bucket);
}

inline fn attributeNameHash(name: []const u8) u64 {
    // Duplicate detection is always verified with an exact byte comparison, so
    // this hash only needs to spread the prefix/length well enough for the
    // 64-slot local table. One multiply is sufficient and materially cheaper
    // than a full general-purpose 64-bit finalizer.
    var mixed = scanner.prefixKey(name) ^ (@as(u64, name.len) << 56);
    mixed *%= 0x9e3779b97f4a7c15;
    mixed ^= mixed >> 32;
    return mixed;
}

noinline fn validateUniqueAttributesQuadratic(input: []const u8, start: usize, end: usize) ParseError!void {
    var i = start;
    while (try scanValidatedAttributeToken(input, i, end)) |current| {
        const current_name = input[current.name_start..current.name_end];
        var previous_i = start;
        while (previous_i < current.name_start) {
            const previous = (try scanValidatedAttributeToken(input, previous_i, end)) orelse break;
            if (previous.name_start == current.name_start) break;
            if (std.mem.eql(u8, input[previous.name_start..previous.name_end], current_name)) {
                return error.DuplicateAttribute;
            }
            previous_i = previous.next;
        }
        i = current.next;
    }
}

noinline fn validateUniqueAttributesRaw(input: []const u8, start: usize, end: usize) ParseError!void {
    if (end - start > 64) return validateUniqueAttributesRawLarge(input, start, end);

    const table_capacity = 64;
    const NameSlot = struct {
        hash: u64,
        start: usize,
        end: usize,
    };

    var slots: [table_capacity]NameSlot = undefined;
    var occupied: u64 = 0;
    var seen_count: usize = 0;
    var i = start;
    while (try scanValidatedAttributeToken(input, i, end)) |current| {
        if (seen_count == table_capacity) {
            // Extremely attribute-heavy tags are outside the fast-path budget.
            // Re-run the exact bounded-memory checker rather than allocating.
            return validateUniqueAttributesQuadratic(input, start, end);
        }

        const current_name = input[current.name_start..current.name_end];
        const hash = attributeNameHash(current_name);
        var slot_index: usize = @intCast(hash >> (64 - 6));
        while (occupied & (@as(u64, 1) << @as(u6, @intCast(slot_index))) != 0) {
            const previous = slots[slot_index];
            if (previous.hash == hash and
                previous.end - previous.start == current.name_end - current.name_start and
                std.mem.eql(u8, input[previous.start..previous.end], current_name))
            {
                return error.DuplicateAttribute;
            }
            slot_index = (slot_index + 1) & (table_capacity - 1);
        }
        slots[slot_index] = .{
            .hash = hash,
            .start = current.name_start,
            .end = current.name_end,
        };
        occupied |= @as(u64, 1) << @as(u6, @intCast(slot_index));
        seen_count += 1;
        i = current.next;
    }
}

noinline fn validateUniqueAttributesRawLarge(input: []const u8, start: usize, end: usize) ParseError!void {
    const table_capacity = 64;
    const NameSlot = struct {
        hash: u64,
        start: usize,
        end: usize,
    };

    var slots: [table_capacity]NameSlot = undefined;
    var occupied: u64 = 0;
    var seen_count: usize = 0;
    var i = start;
    while (try scanValidatedAttributeTokenLarge(input, i, end)) |current| {
        if (seen_count == table_capacity) {
            // Extremely attribute-heavy tags are outside the fast-path budget.
            // Re-run the exact bounded-memory checker rather than allocating.
            return validateUniqueAttributesQuadratic(input, start, end);
        }

        const current_name = input[current.name_start..current.name_end];
        const hash = attributeNameHash(current_name);
        var slot_index: usize = @intCast(hash >> (64 - 6));
        while (occupied & (@as(u64, 1) << @as(u6, @intCast(slot_index))) != 0) {
            const previous = slots[slot_index];
            if (previous.hash == hash and
                previous.end - previous.start == current.name_end - current.name_start and
                std.mem.eql(u8, input[previous.start..previous.end], current_name))
            {
                return error.DuplicateAttribute;
            }
            slot_index = (slot_index + 1) & (table_capacity - 1);
        }
        slots[slot_index] = .{
            .hash = hash,
            .start = current.name_start,
            .end = current.name_end,
        };
        occupied |= @as(u64, 1) << @as(u6, @intCast(slot_index));
        seen_count += 1;
        i = current.next;
    }
}

fn scanClosingTag(input: []const u8, start: usize, comptime strict: bool, comptime incremental: bool) ParseError!CloseToken {
    var i = start + 2;
    if (i < input.len and tables.isWhitespace(input[i])) {
        if (strict) return error.InvalidClosingTagName;
        i = skipWsMode(input, i, strict);
    }
    if (i >= input.len) return error.UnexpectedEndOfData;
    if (!tables.isNameStart(input[i])) return error.InvalidClosingTagName;
    const name_start = i;
    const name_scan = scanner.scanNameAndKey(input, i);
    const name_end = name_scan.end;
    if (comptime strict) {
        if (name_scan.needs_unicode_validation and !document.isValidXmlName(input[name_start..name_end])) return error.InvalidClosingTagName;
    }
    i = name_end;
    if (i < input.len and tables.isWhitespace(input[i])) i = skipWsMode(input, i, strict);
    if (i >= input.len) {
        if (!strict and !incremental) return error.InvalidClosingTagName;
        return error.UnexpectedEndOfData;
    }
    if (input[i] != '>') return error.InvalidClosingTagName;
    return .{ .next = i + 1, .name = .{ .start = @intCast(name_start), .end = @intCast(name_end) }, .key = name_scan.key };
}

fn skipPi(input: []const u8, start: usize, comptime strict: bool, comptime incremental: bool) ParseError!usize {
    if (comptime strict) {
        var i = start + 2;
        if (i >= input.len) {
            if (incremental) return error.UnexpectedEndOfData;
            return error.ExpectedPiTarget;
        }
        if (!tables.isNameStart(input[i])) return error.ExpectedPiTarget;
        const target_start = i;
        const target_scan = scanner.scanNameEndAfterStart(input, i);
        i = target_scan.end;
        const target = input[target_start..i];
        if (target_scan.needs_unicode_validation and !document.isValidXmlName(target)) return error.ExpectedPiTarget;
        if (target.len == 3 and std.ascii.eqlIgnoreCase(target, "xml")) {
            if (!std.mem.eql(u8, target, "xml")) return error.ExpectedPiTarget;
            return error.InvalidDeclaration;
        }
        if (i >= input.len) return error.UnexpectedEndOfData;
        if (!tables.isWhitespace(input[i])) {
            if (input[i] != '?') return error.ExpectedGt;
            if (i + 1 >= input.len) return error.UnexpectedEndOfData;
            if (input[i + 1] != '>') return error.ExpectedGt;
        }
    }

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
        if (comptime strict) try validateComment(input[start + 4 .. end]);
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
        if (strict and !scanner.isDoctypeExact(input, start)) return error.ExpectedGt;
        if (strict) return error.InvalidDoctype;
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

inline fn containsForbiddenCdataClose(input: []const u8, start: usize, end: usize, has_close_bracket: bool) bool {
    // A cumulative range can begin in the middle of `]]>`. Check only the
    // two possible cross-boundary starts, then scan the current range only if
    // it actually contains `]`.
    if (start != 0) {
        const boundary_start = start - @min(start, 2);
        const boundary_end = @min(end, start +| 2);
        if (std.mem.indexOf(u8, input[boundary_start..boundary_end], "]]>") != null) return true;
    }
    return has_close_bracket and std.mem.indexOf(u8, input[start..end], "]]>") != null;
}

inline fn validateAttributeValue(value: []const u8) ParseError!void {
    const specials = scanner.bytePairPresence(value, '<', '&');
    if (specials.first) return error.InvalidAttributeValue;
    if (specials.second) try document.validateXmlAttributeReferences(value, null, false);
}

inline fn validateComment(value: []const u8) ParseError!void {
    if (std.mem.indexOf(u8, value, "--") != null or (value.len != 0 and value[value.len - 1] == '-')) return error.InvalidComment;
}

inline fn validateCharacterDataSpecials(
    input: []const u8,
    start: usize,
    end: usize,
    has_close_bracket: bool,
    has_ampersand: bool,
    comptime incremental: bool,
) ParseError!void {
    std.debug.assert(start <= end and end <= input.len);
    if (containsForbiddenCdataClose(input, start, end, has_close_bracket)) return error.InvalidCharacterData;
    if (has_ampersand) try document.validateXmlReferences(input[start..end], incremental and end == input.len, null, false);
}

inline fn validateCharacterDataRange(input: []const u8, start: usize, end: usize, comptime incremental: bool) ParseError!void {
    std.debug.assert(start <= end and end <= input.len);
    const specials = scanner.bytePairPresence(input[start..end], ']', '&');
    try validateCharacterDataSpecials(input, start, end, specials.first, specials.second, incremental);
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

test "streaming strict character-data validation crosses cumulative chunk boundaries" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const source = "<r>a]]>b</r>";

    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    inline for (.{ 5, 6 }) |split| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};

        try std.testing.expect(try parser.parseAvailable(source[0..split], &ctx, Ctx.onNode));
        try std.testing.expectError(error.InvalidCharacterData, parser.parseAvailable(source, &ctx, Ctx.onNode));
    }
}

test "streaming skipped-subtree character-data validation crosses cumulative chunk boundaries" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const source = "<r><skip>a]]>b</skip></r>";

    const Ctx = struct {
        fn onNode(_: *@This(), node: Event) bool {
            return !(node.kind == .element and std.mem.eql(u8, node.nameSlice(), "skip"));
        }
    };

    inline for (.{ 11, 12 }) |split| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};

        try std.testing.expect(try parser.parseAvailable(source[0..split], &ctx, Ctx.onNode));
        try std.testing.expectError(error.InvalidCharacterData, parser.parseAvailable(source, &ctx, Ctx.onNode));
    }
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

test "streaming parseAvailable accepts references split at every byte" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const source = "<r a='&amp;&#65;&#x42;'>&lt;&#9;&#xA;</r>";

    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
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
    }
}

test "streaming strict enforces declared parsed general entities" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), node: Event) bool {
            return !(node.kind == .element and std.mem.eql(u8, node.nameSlice(), "skip"));
        }
    };

    const invalid_entities = [_][]const u8{
        "<r>&custom;</r>",
        "<!DOCTYPE r [<!NOTATION n SYSTEM 'urn:n'><!ENTITY custom SYSTEM 'urn:x' NDATA n>]><r>&custom;</r>",
        "<?xml version='1.0' standalone='yes'?><!DOCTYPE r SYSTEM 'urn:external'><r>&external;</r>",
        "<!DOCTYPE r><r><skip><x a='&custom;'/></skip></r>",
        "<!DOCTYPE r SYSTEM 'urn:subset' [<!NOTATION n SYSTEM 'urn:n'><!ENTITY raw SYSTEM 'urn:x' NDATA n>]><r>&raw;</r>",
    };
    inline for (invalid_entities) |source| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try std.testing.expectError(error.InvalidNumericCharacterEntity, parser.parse(source, &ctx, Ctx.onNode));
    }

    {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        const source = "<!DOCTYPE r [<!ENTITY external SYSTEM 'urn:x'>]><r a='&external;'/>";
        try std.testing.expectError(error.InvalidAttributeValue, parser.parse(source, &ctx, Ctx.onNode));
    }

    const valid = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY custom 'x'>]><r>&custom;</r>",
        "<!DOCTYPE r SYSTEM 'urn:external'><r>&external;</r>",
        "<!DOCTYPE r [<!ENTITY external SYSTEM 'urn:x'>]><r>&external;</r>",
    };
    inline for (valid) |source| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try parser.parse(source, &ctx, Ctx.onNode);
    }
}

test "streaming strict validates used entity replacement graphs" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    const invalid_entity = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY a '&missing;'>]><r>&a;</r>",
        "<!DOCTYPE r [<!NOTATION n SYSTEM 'n'><!ENTITY e SYSTEM 'x' NDATA n><!ENTITY a '&e;'>]><r>&a;</r>",
    };
    inline for (invalid_entity) |source| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try std.testing.expectError(error.InvalidNumericCharacterEntity, parser.parse(source, &ctx, Ctx.onNode));
    }

    {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        const source = "<!DOCTYPE r [<!ENTITY a '&b;'><!ENTITY b '&a;'>]><r>&a;</r>";
        try std.testing.expectError(error.RecursiveEntity, parser.parse(source, &ctx, Ctx.onNode));
    }
    {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        const source = "<!DOCTYPE r [<!ENTITY a '&e;'><!ENTITY e SYSTEM 'x'>]><r x='&a;'/>";
        try std.testing.expectError(error.InvalidAttributeValue, parser.parse(source, &ctx, Ctx.onNode));
    }
    {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        const source = "<!DOCTYPE r [<!ENTITY a '&#60;'>]><r x='&a;'/>";
        try std.testing.expectError(error.InvalidAttributeValue, parser.parse(source, &ctx, Ctx.onNode));
    }

    const valid = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY a '&b;'><!ENTITY b 'ok'>]><r>&a;</r>",
        "<!DOCTYPE r [<!ENTITY a '&lt;'>]><r x='&a;'/>",
        "<!DOCTYPE r [<!ENTITY a '&#38;lt;'>]><r x='&a;'/>",
    };
    inline for (valid) |source| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try parser.parse(source, &ctx, Ctx.onNode);
    }
}

test "streaming strict validates internal parameter entity replacement text" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    const invalid = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY % p 'x'>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % p '<!ELEMENT>'>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % q 'x'><!ENTITY % p '&#37;q;'>%p;]><r/>",
    };
    inline for (invalid) |source| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try std.testing.expectError(error.InvalidDoctype, parser.parse(source, &ctx, Ctx.onNode));
    }

    const valid = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY % p '<!ELEMENT r EMPTY>'>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % q '<!ELEMENT r EMPTY>'><!ENTITY % p '&#37;q;'>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % p SYSTEM 'urn:external'>%p;]><r/>",
    };
    inline for (valid) |source| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try parser.parse(source, &ctx, Ctx.onNode);
    }
}

test "streaming strict applies entity constraints to declarations from parameter entities" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    const cases = [_]struct { source: []const u8, err: ParseError }{
        .{ .source = "<!DOCTYPE r [<!NOTATION n SYSTEM 'n'><!ENTITY % p \"<!ENTITY e SYSTEM 'x' NDATA n>\">%p;]><r>&e;</r>", .err = error.InvalidNumericCharacterEntity },
        .{ .source = "<!DOCTYPE r [<!ENTITY % p \"<!ENTITY e SYSTEM 'x'>\">%p;]><r a='&e;'/>", .err = error.InvalidAttributeValue },
        .{ .source = "<!DOCTYPE r [<!ENTITY % p \"<!ENTITY e '&#60;'>\">%p;]><r a='&e;'/>", .err = error.InvalidAttributeValue },
        .{ .source = "<!DOCTYPE r [<!ENTITY % p \"<!ENTITY e '&e;'>\">%p;]><r>&e;</r>", .err = error.RecursiveEntity },
        .{ .source = "<?xml version='1.0' standalone='yes'?><!DOCTYPE r [%unknown;]><r/>", .err = error.InvalidDoctype },
    };
    inline for (cases) |case| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try std.testing.expectError(case.err, parser.parse(case.source, &ctx, Ctx.onNode));
    }

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    try parser.parse("<!DOCTYPE r [<!ENTITY % p \"<!ENTITY e 'ok'>\">%p;]><r>&e;</r>", &ctx, Ctx.onNode);
}

test "streaming strict validates DTD attribute default entity constraints" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    const invalid_entity = [_][]const u8{
        "<!DOCTYPE r [<!ATTLIST r a CDATA '&e;'><!ENTITY e 'x'>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA '&e;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY e '&x;'><!ATTLIST r a CDATA '&e;'><!ENTITY x 'v'>]><r/>",
        "<?xml version='1.0' standalone='yes'?><!DOCTYPE r SYSTEM 'urn:missing' [<!ATTLIST r a CDATA '&e;'>]><r/>",
    };
    inline for (invalid_entity) |source| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try std.testing.expectError(error.InvalidNumericCharacterEntity, parser.parse(source, &ctx, Ctx.onNode));
    }

    const invalid_attribute = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY e SYSTEM 'x'><!ATTLIST r a CDATA '&e;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY e '<'><!ATTLIST r a CDATA '&e;'>]><r/>",
    };
    inline for (invalid_attribute) |source| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try std.testing.expectError(error.InvalidAttributeValue, parser.parse(source, &ctx, Ctx.onNode));
    }

    const valid = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY e 'x'><!ATTLIST r a CDATA '&e;'>]><r/>",
        "<!DOCTYPE r SYSTEM 'urn:missing' [<!ATTLIST r a CDATA '&external;'>]><r/>",
    };
    inline for (valid) |source| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try parser.parse(source, &ctx, Ctx.onNode);
    }
}

test "streaming cumulative declared entities survive every split and restore" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const source = "<!DOCTYPE r [<!ENTITY custom 'x'>]><r a='&custom;'>&custom;</r>";
    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    for (0..source.len + 1) |split| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        _ = try parser.parseAvailable(source[0..split], &ctx, Ctx.onNode);
        const state = parser.save();
        parser.restore(state);
        try std.testing.expect(try parser.parseAvailable(source, &ctx, Ctx.onNode));
        try parser.finish();
    }
}

test "streaming strict validates XML Unicode and names" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        skip_root: bool = false,

        fn onNode(self: *@This(), node: Event) bool {
            return !(self.skip_root and node.kind == .element and node.depth == 0);
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    const invalid_xml = [_][]const u8{
        "<r>\xC0\xAF</r>",
        "<r><!--\xC0\xAF--></r>",
        "<r>\x01</r>",
    };
    for (invalid_xml) |source| {
        try std.testing.expectError(error.InvalidXmlCharacter, parser.parse(source, &ctx, Ctx.onNode));
    }

    const invalid_names = [_]struct { source: []const u8, err: ParseError }{
        .{ .source = "<\xC3\x97/>", .err = error.ExpectedElementName },
        .{ .source = "<r \xC3\x97='x'/>", .err = error.ExpectedAttributeName },
        .{ .source = "<?\xC3\x97?><r/>", .err = error.ExpectedPiTarget },
        .{ .source = "<r></\xC3\x97>", .err = error.InvalidClosingTagName },
    };
    for (invalid_names) |case| {
        try std.testing.expectError(case.err, parser.parse(case.source, &ctx, Ctx.onNode));
    }

    try parser.parse("<\xC3\xA9l\xC3\xA9ment \xCE\xB1='ok'><\xCE\xB2/></\xC3\xA9l\xC3\xA9ment>", &ctx, Ctx.onNode);

    ctx.skip_root = true;
    try std.testing.expectError(error.ExpectedElementName, parser.parse("<r><\xC3\x97/></r>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.ExpectedAttributeName, parser.parse("<r><x \xC3\x97='v'/></r>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidAttributeValue, parser.parse("<r><x a='x<y'/></r>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.ExpectedPiTarget, parser.parse("<r><?\xC3\x97?></r>", &ctx, Ctx.onNode));
}

test "streaming strict cumulative UTF-8 validation handles split sequences and restore" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
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

    try std.testing.expect(try parser.parseAvailable("<r>", &ctx, Ctx.onNode));
    const state = parser.save();
    try std.testing.expect(!(try parser.parseAvailable("<r> \xC3", &ctx, Ctx.onNode)));
    try std.testing.expect(parser.needs_more);
    try std.testing.expect(try parser.parseAvailable("<r> \xC3\xA9</r>", &ctx, Ctx.onNode));
    try parser.finish();

    parser.restore(state);
    try std.testing.expectError(error.InvalidXmlCharacter, parser.parseAvailable("<r>\xC3(</r>", &ctx, Ctx.onNode));
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
        "<r a='x<y'/>",
        "<r><!--a--b--></r>",
        "<r><!--a---></r>",
        "<r>x]]>y</r>",
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

test "streaming turbo followingTextRaw uses turbo token grammar" {
    const opts: ParseOptions = .{ .mode = .turbo };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        saw_tail: bool = false,
        fn onNode(self: *@This(), node: Event) bool {
            if (node.kind == .element and std.mem.eql(u8, node.nameSlice(), "skip")) {
                self.saw_tail = std.mem.eql(u8, node.followingTextRaw() catch return false, "tail");
                return false;
            }
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    try parser.parse("<r><skip><x a=1/></skip>tail</r>", &ctx, Ctx.onNode);
    try std.testing.expect(ctx.saw_tail);
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

test "streaming skipped subtrees preserve strict token validation" {
    const EventValidated = Types(.{ .mode = .strict, .validate_closing_tags = true }).Node;
    const ValidatedParser = Types(.{ .mode = .strict, .validate_closing_tags = true }).Parser;
    const ValidatedCtx = struct {
        fn onNode(_: *@This(), node: EventValidated) bool {
            return !(node.kind == .element and std.mem.eql(u8, node.nameSlice(), "skip"));
        }
    };

    var validated = ValidatedParser.init(std.testing.allocator);
    defer validated.deinit();
    var validated_ctx: ValidatedCtx = .{};
    try std.testing.expectError(error.ExpectedPiTarget, validated.parse("<skip><? ?></skip>", &validated_ctx, ValidatedCtx.onNode));
    validated.clear();
    try std.testing.expectError(error.ExpectedPiTarget, validated.parse("<skip><?XML x?></skip>", &validated_ctx, ValidatedCtx.onNode));

    const EventSyntaxOnly = Types(.{ .mode = .strict, .validate_closing_tags = false }).Node;
    const SyntaxOnlyParser = Types(.{ .mode = .strict, .validate_closing_tags = false }).Parser;
    const SyntaxOnlyCtx = struct {
        fn onNode(_: *@This(), node: EventSyntaxOnly) bool {
            return !(node.kind == .element and std.mem.eql(u8, node.nameSlice(), "skip"));
        }
    };

    var syntax_only = SyntaxOnlyParser.init(std.testing.allocator);
    defer syntax_only.deinit();
    var syntax_ctx: SyntaxOnlyCtx = .{};
    try std.testing.expectError(error.InvalidClosingTagName, syntax_only.parse("<skip><x/></ ></skip>", &syntax_ctx, SyntaxOnlyCtx.onNode));
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

test "streaming turbo accepts mixed XML whitespace around attribute equals" {
    const opts: ParseOptions = .{
        .mode = .turbo,
        .validate_closing_tags = true,
        .require_closed_elements_on_eof = true,
    };
    const T = Types(opts);
    const input = "<r a \n \t=\r \"x>y\"><b/></r \n>";

    const Context = struct {
        saw_root: bool = false,
        saw_child: bool = false,

        fn onNode(self: *@This(), node: T.Node) bool {
            if (node.kind != .element) return true;
            if (std.mem.eql(u8, node.nameSlice(), "r")) {
                self.saw_root = std.mem.eql(u8, node.getAttributeValueRaw("a") orelse "", "x>y");
            } else if (std.mem.eql(u8, node.nameSlice(), "b")) {
                self.saw_child = true;
            }
            return true;
        }
    };

    var parser = T.Parser.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Context = .{};
    try parser.parse(input, &ctx, Context.onNode);
    try std.testing.expect(ctx.saw_root);
    try std.testing.expect(ctx.saw_child);
}

test "streaming strict accepts mixed XML whitespace between attributes" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        count: usize = 0,
        fn onNode(self: *@This(), _: Event) bool {
            self.count += 1;
            return true;
        }
    };
    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    try parser.parse("<r \n\t a='1' \r\n b=\"2\">x</r>", &ctx, Ctx.onNode);
    try std.testing.expectEqual(@as(usize, 2), ctx.count);
}

test "streaming public save restore preserves closing-tag stack across divergent continuations" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        fn onNode(_: *@This(), _: *const Event) bool {
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expect(try parser.parseAvailable("<a>", &ctx, Ctx.onNode));
    const state = parser.save();

    // Pop the saved <a> and then overwrite that stack slot with <b>.
    try std.testing.expect(try parser.parseAvailable("<a><a></a><b>", &ctx, Ctx.onNode));

    parser.restore(state);
    try std.testing.expect(try parser.parseAvailable("<a><a></a></a>", &ctx, Ctx.onNode));
    try parser.finish();
}

test "streaming public save restore preserves skipped-subtree stack across divergent continuations" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        fn onNode(_: *@This(), node: *const Event) bool {
            return !std.mem.eql(u8, node.nameSlice(), "skip");
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expect(try parser.parseAvailable("<r><skip><a>", &ctx, Ctx.onNode));
    const state = parser.save();

    try std.testing.expect(try parser.parseAvailable("<r><skip><a></a></skip><b>", &ctx, Ctx.onNode));

    parser.restore(state);
    try std.testing.expect(try parser.parseAvailable("<r><skip><a></a><c></c></skip></r>", &ctx, Ctx.onNode));
    try parser.finish();
}

test "streaming cumulative strict parsing rejects malformed tokens at every split" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true, .include_misc_nodes = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };
    const cases = [_][]const u8{
        "<r>",           "<r></x>",         "<r></ r>",           "<r></r x>",         "<r a=1/>",                          "<r a='x<y'/>",
        "<r>&#X41;</r>", "<r>&#0;</r>",     "<r>&#xD800;</r>",    "<r>&#x110000;</r>", "<r>&;</r>",                         "<r>&1x;</r>",
        "<r>&amp</r>",   "<r a='&#0;'/>",   "<r a='&#X41;'/>",    "<r a='&1x;'/>",     "<r a='&amp'/>",                     "<r a='a&b'/>",
        "<r a='x>",      "<r a='x'b='y'/>", "<r><!--a--b--></r>", "<r><!--a---></r>",  "<r>a]]>b</r>",                      "<? ?>",
        "<?XML x?>",     "<r><? ?></r>",    "<r><?XML x?></r>",   "<!doctype r><r/>",  "<!DOCTYPE r [<!ELEMENT r ANY><r/>", "<r><!foo</r>",
        "<r><x/",        "<r><x a='1'",     "<r><![CDATA[x</r>",  "<r><!--x</r>",      "<r><?pi x</r>",                     "<",
    };

    for (cases) |source| {
        var full = ParserType.init(std.testing.allocator);
        defer full.deinit();
        var full_ctx: Ctx = .{};
        var full_name: []const u8 = "OK";
        full.parse(source, &full_ctx, Ctx.onNode) catch |err| {
            full_name = @errorName(err);
        };
        try std.testing.expect(!std.mem.eql(u8, full_name, "OK"));

        for (0..source.len + 1) |split| {
            var inc = ParserType.init(std.testing.allocator);
            defer inc.deinit();
            var inc_ctx: Ctx = .{};
            var inc_name: []const u8 = "OK";
            var failed = false;
            _ = inc.parseAvailable(source[0..split], &inc_ctx, Ctx.onNode) catch |err| {
                inc_name = @errorName(err);
                failed = true;
            };
            if (!failed) {
                _ = inc.parseAvailable(source, &inc_ctx, Ctx.onNode) catch |err| {
                    inc_name = @errorName(err);
                    failed = true;
                };
            }
            if (!failed) {
                inc.finish() catch |err| {
                    inc_name = @errorName(err);
                };
            }
            if (std.mem.eql(u8, inc_name, "OK")) {
                std.debug.print("incremental accepted malformed source={s} split={d}; full={s}\n", .{ source, split, full_name });
                return error.TestExpectedError;
            }
        }
    }
}

test "streaming turbo attribute iterator skips tolerated separators" {
    const opts: ParseOptions = .{ .mode = .turbo };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;

    const Ctx = struct {
        saw_attr: bool = false,
        fn onNode(self: *@This(), node: Event) bool {
            if (node.kind == .element and std.mem.eql(u8, node.nameSlice(), "r")) {
                self.saw_attr = std.mem.eql(u8, node.getAttributeValueRaw("a") orelse return false, "1");
            }
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    try parser.parse("<r ! a='1'/>", &ctx, Ctx.onNode);
    try std.testing.expect(ctx.saw_attr);
}

test "streaming followingTextRaw honors closing-tag validation" {
    const source = "<skip><x></skip></x>tail";

    inline for (.{
        ParseOptions{ .mode = .strict, .validate_closing_tags = true },
        ParseOptions{ .mode = .turbo, .validate_closing_tags = true },
    }) |opts| {
        const Event = Types(opts).Node;
        const node: Event = .{
            .source = source,
            .kind = .element,
            .depth = 0,
            .name = .{ .start = 1, .end = 5 },
            .token_end = 6,
        };
        try std.testing.expectError(error.InvalidClosingTagName, node.followingTextRaw());
    }
}

test "streaming turbo rejects unterminated quoted attributes like DOM" {
    const opts: ParseOptions = .{ .mode = .turbo };
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
    try std.testing.expectError(error.UnexpectedEndOfData, parser.parse("<a x='1></a>", &ctx, Ctx.onNode));
}

test "streaming turbo closing validation rejects truncated closing tags" {
    const opts: ParseOptions = .{ .mode = .turbo, .validate_closing_tags = true, .require_closed_elements_on_eof = false };
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
    try std.testing.expectError(error.InvalidClosingTagName, parser.parse("text</X", &ctx, Ctx.onNode));
}

test "streaming turbo closing validation rejects a named close missing gt" {
    const opts: ParseOptions = .{ .mode = .turbo, .validate_closing_tags = true, .require_closed_elements_on_eof = false };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: Event) bool {
            return true;
        }
    };

    const cases = [_][]const u8{
        "<a></a",
        "<a></a ",
        "<a></b",
    };
    for (cases) |input| {
        var parser = ParserType.init(std.testing.allocator);
        defer parser.deinit();
        var ctx: Ctx = .{};
        try std.testing.expectError(error.InvalidClosingTagName, parser.parse(input, &ctx, Ctx.onNode));
    }
}

test "streaming skipped turbo subtree rejects a named close missing gt" {
    const opts: ParseOptions = .{ .mode = .turbo, .validate_closing_tags = true, .require_closed_elements_on_eof = false };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), node: Event) bool {
            return node.kind != .element;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    try std.testing.expectError(error.InvalidClosingTagName, parser.parse("<a></X", &ctx, Ctx.onNode));
}

test "streaming skipped turbo subtree preserves required-closure errors" {
    const opts: ParseOptions = .{ .mode = .turbo, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), node: Event) bool {
            return !(node.kind == .element and std.mem.eql(u8, node.nameSlice(), "b"));
        }
    };
    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    try std.testing.expectError(error.UnexpectedEndOfData, parser.parse("<b>< unfinished", &ctx, Ctx.onNode));
}

test "streaming strict enforces document-level well-formedness" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true, .include_misc_nodes = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: *const Event) bool {
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expectError(error.ExpectedDocumentElement, parser.parse("", &ctx, Ctx.onNode));
    try std.testing.expectError(error.ExpectedDocumentElement, parser.parse("<!--only misc-->", &ctx, Ctx.onNode));
    try std.testing.expectError(error.MultipleDocumentElements, parser.parse("<a/><b/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidDocumentContent, parser.parse("text<a/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidDocumentContent, parser.parse("<a/>text", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidDocumentContent, parser.parse("<![CDATA[x]]><a/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidDoctype, parser.parse("<!DOCTYPE a><!DOCTYPE a><a/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidDoctype, parser.parse("<a/><!DOCTYPE a>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidDoctype, parser.parse("<a><!DOCTYPE a></a>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidDeclaration, parser.parse(" <?xml version='1.0'?><a/>", &ctx, Ctx.onNode));
    try std.testing.expectError(error.InvalidDeclaration, parser.parse("<?pi x?><?xml version='1.0'?><a/>", &ctx, Ctx.onNode));

    try parser.parse("<?xml version='1.0'?><!--x--><!DOCTYPE a><a><![CDATA[x]]></a><?pi y?>", &ctx, Ctx.onNode);
}

test "streaming strict validates processing instruction separators" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: *const Event) bool {
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    const invalid = [_][]const u8{
        "<?pi=data?><r/>",
        "<?pi/data?><r/>",
        "<r><?pi:data/x?></r>",
    };
    inline for (invalid) |source| {
        try std.testing.expectError(error.ExpectedGt, parser.parse(source, &ctx, Ctx.onNode));
    }

    try parser.parse("<?pi?><r/>", &ctx, Ctx.onNode);
    try parser.parse("<?pi data?><r/>", &ctx, Ctx.onNode);
}

test "streaming strict save restore preserves document-level state" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: *const Event) bool {
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};

    try std.testing.expect(try parser.parseAvailable("<!DOCTYPE a>", &ctx, Ctx.onNode));
    const state = parser.save();
    try std.testing.expect(try parser.parseAvailable("<!DOCTYPE a><a/>", &ctx, Ctx.onNode));
    parser.restore(state);
    try std.testing.expect(try parser.parseAvailable("<!DOCTYPE a><b/>", &ctx, Ctx.onNode));
    try parser.finish();
}

test "streaming strict rejects duplicate attribute names including skipped subtrees" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        skip_root: bool = false,
        fn onNode(self: *@This(), node: *const Event) bool {
            if (self.skip_root and node.kind == .element and node.depth == 0) return false;
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    try std.testing.expectError(error.DuplicateAttribute, parser.parse("<r a='1' a='2'/>", &ctx, Ctx.onNode));
    try parser.parse("<r a0='0' a1='1' a2='2' a3='3' a4='4' a5='5' a6='6' a7='7' a8='8' a9='9'/>", &ctx, Ctx.onNode);
    // Distinct names that land in the same hash-table bucket must probe rather
    // than false-positive as duplicates.
    try parser.parse("<r h='1' ab='2' z='3'/>", &ctx, Ctx.onNode);
    try std.testing.expectError(error.DuplicateAttribute, parser.parse("<r a='1' b='2' c='3' a='4'/>", &ctx, Ctx.onNode));
    // ':' and 'z' share the same low six bits, so the one-byte fast bucket
    // must keep them distinct while still catching a repeated ':'.
    try parser.parse("<r :='1' z='2' a='3'/>", &ctx, Ctx.onNode);
    try std.testing.expectError(error.DuplicateAttribute, parser.parse("<r :='1' z='2' a='3' :='4'/>", &ctx, Ctx.onNode));

    var many = std.ArrayList(u8).empty;
    defer many.deinit(std.testing.allocator);
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..65) |index| try many.print(std.testing.allocator, " a{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, "/>");
    try parser.parse(many.items, &ctx, Ctx.onNode);
    many.items.len -= 2;
    try many.appendSlice(std.testing.allocator, " a63='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, parser.parse(many.items, &ctx, Ctx.onNode));
    try std.testing.expectError(
        error.DuplicateAttribute,
        parser.parse("<r a0='0' a1='1' a2='2' a3='3' a4='4' a5='5' a6='6' a7='7' a8='8' a9='9' a8='x'/>", &ctx, Ctx.onNode),
    );

    ctx.skip_root = true;
    try std.testing.expectError(error.DuplicateAttribute, parser.parse("<r><x a='1' a='2'/></r>", &ctx, Ctx.onNode));
    try std.testing.expectError(
        error.DuplicateAttribute,
        parser.parse("<r><x a0='0' a1='1' a2='2' a3='3' a4='4' a5='5' a6='6' a7='7' a8='8' a9='9' a8='x'/></r>", &ctx, Ctx.onNode),
    );
}

test "streaming strict validates XML declaration grammar" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: *const Event) bool {
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    const invalid = [_][]const u8{
        "<?xml?><r/>",
        "<?xml encoding='UTF-8'?><r/>",
        "<?xml version='2.0'?><r/>",
        "<?xml version='1.0'encoding='UTF-8'?><r/>",
        "<?xml version='1.0' standalone='maybe'?><r/>",
        "<?xml version='1.0' extra='x'?><r/>",
    };
    for (invalid) |source| try std.testing.expectError(error.InvalidDeclaration, parser.parse(source, &ctx, Ctx.onNode));
    try parser.parse("<?xml version = '1.0' encoding='UTF-8' standalone=\"yes\" ?><r/>", &ctx, Ctx.onNode);
}

test "streaming strict validates DOCTYPE grammar" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    const ParserType = Types(opts).Parser;
    const Event = Types(opts).Node;
    const Ctx = struct {
        fn onNode(_: *@This(), _: *const Event) bool {
            return true;
        }
    };

    var parser = ParserType.init(std.testing.allocator);
    defer parser.deinit();
    var ctx: Ctx = .{};
    const invalid = [_][]const u8{
        "<!DOCTYPE><r/>",
        "<!DOCTYPEr><r/>",
        "<!DOCTYPE 1r><r/>",
        "<!DOCTYPE r garbage><r/>",
        "<!DOCTYPE r SYSTEM'urn:test'><r/>",
        "<!DOCTYPE r PUBLIC 'id'><r/>",
        "<!DOCTYPE r PUBLIC '^' 'sys'><r/>",
        "<!DOCTYPE r [junk]><r/>",
        "<!DOCTYPE r [<!FOO x>]><r/>",
        "<!DOCTYPE r [<![IGNORE[x]]>]><r/>",
        "<!DOCTYPE r [<!--a--b-->]><r/>",
        "<!DOCTYPE r [<!--a--->]><r/>",
        "<!DOCTYPE r [<?xml x?>]><r/>",
        "<!DOCTYPE r [<??>]><r/>",
        "<!DOCTYPE r [%missing]><r/>",
        "<!DOCTYPE r [<!ELEMENT r>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r ANYx>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r ()>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (a|)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (a,b|c)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (a b)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (#PCDATA|a)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (#PCDATA,a)*>]><r/>",
        "<!DOCTYPE r [<!ELEMENT \xC3\x97 EMPTY>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a UNKNOWN #IMPLIED>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a () #IMPLIED>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a NOTATION () #IMPLIED>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a (one|two)>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA 'x<y'>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA '&#0;'>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA '&#X41;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY x>]><r/>",
        "<!DOCTYPE r [<!ENTITY x PUBLIC 'id'>]><r/>",
        "<!DOCTYPE r [<!ENTITY %p 'x'>]><r/>",
        "<!DOCTYPE r [<!ENTITY % p SYSTEM 'x' NDATA n>]><r/>",
        "<!DOCTYPE r [<!ENTITY x '%p;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY x '&#xD800;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY x '&#x110000;'>]><r/>",
        "<!DOCTYPE r [<!NOTATION n>]><r/>",
        "<!DOCTYPE r [<!NOTATION n SYSTEM>]><r/>",
        "<!DOCTYPE r [<!NOTATION n PUBLIC>]><r/>",
    };
    for (invalid) |source| try std.testing.expectError(error.InvalidDoctype, parser.parse(source, &ctx, Ctx.onNode));

    const valid = [_][]const u8{
        "<!DOCTYPE r SYSTEM 'urn:test'><r/>",
        "<!DOCTYPE r PUBLIC '-//Example//DTD Test 1.0//EN' 'urn:test' [<!ELEMENT r EMPTY>]><r/>",
        "<!DOCTYPE r []><r/>",
        "<!DOCTYPE r [<!--ok--><?pi data?><!ELEMENT r ANY>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (a,(b|c)+,d?)><!ELEMENT a EMPTY><!ELEMENT b EMPTY><!ELEMENT c EMPTY><!ELEMENT d EMPTY>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (#PCDATA)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (#PCDATA|em|b)*>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA #IMPLIED b ID #REQUIRED c (one|two|3) 'one' n NOTATION (gif|jpg) #FIXED 'gif'>]><r/>",
        "<!DOCTYPE r [<!ENTITY x 'a&amp;&#x41;'><!ENTITY ext SYSTEM 'urn:x' NDATA n><!ENTITY % p 'x'><!NOTATION n PUBLIC 'id'>]><r/>",
        "<!DOCTYPE r [<!ENTITY % p SYSTEM 'urn:p'><!NOTATION n SYSTEM 'urn:n'><!NOTATION m PUBLIC 'id' 'urn:m'>]><r/>",
        "<!DOCTYPE r [<!ELEMENT \xC3\xA9l\xC3\xA9ment EMPTY>]><r/>",
    };
    for (valid) |source| try parser.parse(source, &ctx, Ctx.onNode);
}
