const std = @import("std");
const common = @import("common.zig");
const document = @import("document.zig");
const scanner = @import("scanner.zig");
const tables = @import("tables.zig");

const ParseOptions = document.ParseOptions;
const ParseError = document.ParseError;
const NodeType = document.NodeType;
const IndexInt = document.IndexInt;
const InvalidIndex = document.InvalidIndex;

pub fn parseInto(noalias doc: anytype, noalias input: []const u8, comptime opts: ParseOptions) ParseError!void {
    if (!common.lenFits(input.len)) return error.InputTooLarge;
    var p = Parser(opts, @TypeOf(doc.*)){ .doc = doc, .input = input, .i = 0 };
    try p.parse();
}

fn Parser(comptime opts: ParseOptions, comptime DocType: type) type {
    return struct {
        doc: *DocType,
        input: []const u8,
        i: usize,

        const Self = @This();

        const strict_mode = opts.mode == .strict;
        const validate_closing_tags = opts.validate_closing_tags;
        const require_closed_elements_on_eof = opts.require_closed_elements_on_eof;
        const expand_dtd_entities = opts.expand_dtd_entities;
        const drop_whitespace_text_nodes = opts.drop_whitespace_text_nodes;

        fn parse(noalias self: *Self) ParseError!void {
            try self.doc.reserveForInput(self.input.len);
            const root_len = self.doc.nodes.items.len;
            if (root_len == self.doc.nodes.capacity) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, root_len + root_len / 2 + @as(usize, 8)) catch return error.OutOfMemory;
            }
            _ = self.doc.nodes.addOneAssumeCapacity();
            self.doc.nodes.items[0] = .{
                .kind = .document,
                .parent = InvalidIndex,
                .subtree_end = 0,
            };
            try self.pushStack(0, 0, 0);

            while (self.i < self.input.len) {
                if (self.input[self.i] != '<') {
                    const run = scanner.scanTextRun(self.input, self.i);
                    if (run.lt_index > self.i) {
                        if (!drop_whitespace_text_nodes or run.has_non_whitespace) {
                            const parent_idx = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1].idx;
                            _ = try self.appendTextNodeTo(parent_idx, self.i, run.lt_index);
                        }
                    }
                    self.i = run.lt_index;
                    continue;
                }

                if (self.i + 1 >= self.input.len) {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    self.i += 1;
                    break;
                }

                switch (self.input[self.i + 1]) {
                    '/' => try self.parseClosingTag(),
                    '?' => try self.parsePiOrDeclaration(),
                    '!' => try self.parseBangNode(),
                    else => try self.parseOpeningTag(),
                }
            }

            if (require_closed_elements_on_eof and self.doc.parse_stack.items.len > 1) {
                return error.UnexpectedEndOfData;
            }

            while (self.doc.parse_stack.items.len > 1) {
                self.finishNode(self.popStack());
            }
            if (self.doc.nodes.items.len != 0) {
                self.finishNode(0);
            }
        }

        inline fn parseOpeningTag(noalias self: *Self) ParseError!void {
            self.i += 1; // '<'

            if (self.i >= self.input.len) return error.UnexpectedEndOfData;
            if (!tables.isNameStart(self.input[self.i])) {
                if (strict_mode) return error.ExpectedElementName;
                self.i = (scanner.findByte(self.input, self.i, '>') orelse self.input.len);
                if (self.i < self.input.len) self.i += 1;
                return;
            }

            const name_start = self.i;
            const scan = scanNameAndKey(self.input, self.i);
            self.i = scan.end;
            const name_end = scan.end;
            const tag_len = scan.len;
            const tag_key = scan.key;

            const parent_idx = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1].idx;
            const idx = try self.appendElementNodeTo(parent_idx, name_start, name_end);
            var node = &self.doc.nodes.items[idx];

            const attr_start_idx: IndexInt = @intCast(self.doc.attrs.items.len);

            // Common path: start tag with no attributes.
            if (self.i < self.input.len) {
                const c0 = self.input[self.i];
                if (c0 == '>') {
                    self.i += 1;
                    node = &self.doc.nodes.items[idx];
                    node.attr_start = attr_start_idx;
                    node.attr_len = 0;
                    self.skipDroppedWhitespaceText();
                    if (try self.tryFinishSimpleTextElement(idx, name_start, tag_len, tag_key)) {
                        return;
                    }
                    if (comptime validate_closing_tags) {
                        try self.pushStack(idx, tag_key, tag_len);
                    } else {
                        try self.pushStack(idx, 0, 0);
                    }
                    return;
                }

                if (c0 == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    self.i += 2;
                    node = &self.doc.nodes.items[idx];
                    node.attr_start = attr_start_idx;
                    node.attr_len = 0;
                    return;
                }
            }

            while (self.i < self.input.len) {
                self.skipWhitespace();
                if (self.i >= self.input.len) return error.UnexpectedEndOfData;

                const c = self.input[self.i];
                if (c == '>') {
                    self.i += 1;
                    node = &self.doc.nodes.items[idx];
                    node.attr_start = attr_start_idx;
                    node.attr_len = @as(IndexInt, @intCast(self.doc.attrs.items.len)) - attr_start_idx;
                    self.skipDroppedWhitespaceText();
                    if (try self.tryFinishSimpleTextElement(idx, name_start, tag_len, tag_key)) {
                        return;
                    }
                    if (comptime validate_closing_tags) {
                        try self.pushStack(idx, tag_key, tag_len);
                    } else {
                        try self.pushStack(idx, 0, 0);
                    }
                    return;
                }

                if (c == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    self.i += 2;
                    node = &self.doc.nodes.items[idx];
                    node.attr_start = attr_start_idx;
                    node.attr_len = @as(IndexInt, @intCast(self.doc.attrs.items.len)) - attr_start_idx;
                    return;
                }

                try self.parseAttribute();
            }

            return error.UnexpectedEndOfData;
        }

        inline fn parseAttribute(noalias self: *Self) ParseError!void {
            if (self.i >= self.input.len) return error.UnexpectedEndOfData;

            if (!tables.isNameStart(self.input[self.i])) {
                self.i += 1;
                return;
            }

            const name_start = self.i;
            self.i = scanner.findNameEnd(self.input, self.i);
            const name_end = self.i;
            const input = self.input;
            const input_len = input.len;

            var value_start = self.i;
            var value_end = self.i;

            parse_value: {
                if (self.i + 1 < input_len and input[self.i] == '=') {
                    const quote = input[self.i + 1];
                    if (quote == '\'' or quote == '"') {
                        value_start = self.i + 2;
                        if (scanner.findByte(input, value_start, quote)) |quote_pos| {
                            value_end = quote_pos;
                            self.i = quote_pos + 1;
                        } else {
                            if (strict_mode) return error.ExpectedQuote;
                            value_end = input_len;
                            self.i = input_len;
                        }
                        break :parse_value;
                    }
                }

                self.skipWhitespace();

                if (self.i < input_len and input[self.i] == '=') {
                    self.i += 1;
                    self.skipWhitespace();

                    if (self.i >= input_len) return error.UnexpectedEndOfData;

                    const c = input[self.i];
                    if (c == '\'' or c == '"') {
                        const quote = c;
                        self.i += 1;
                        value_start = self.i;
                        if (scanner.findByte(input, self.i, quote)) |quote_pos| {
                            value_end = quote_pos;
                            self.i = quote_pos + 1;
                        } else {
                            if (strict_mode) return error.ExpectedQuote;
                            value_end = input_len;
                            self.i = input_len;
                        }
                    } else {
                        if (strict_mode) return error.ExpectedQuote;
                        value_start = self.i;
                        self.i = scanner.findAttrUnquotedEnd(input, self.i);
                        value_end = self.i;
                    }
                }
            }

            const len = self.doc.attrs.items.len;
            if (len == self.doc.attrs.capacity) {
                @branchHint(.unlikely);
                self.doc.attrs.ensureTotalCapacityPrecise(self.doc.allocator, len + len / 2 + @as(usize, 8)) catch return error.OutOfMemory;
            }
            const out = self.doc.attrs.addOneAssumeCapacity();
            out.* = .{
                .name = .{
                    .start = @intCast(name_start),
                    .end = @intCast(name_end),
                },
                .value = .{
                    .start = @intCast(value_start),
                    .end = @intCast(value_end),
                },
            };
        }

        inline fn parseClosingTag(noalias self: *Self) ParseError!void {
            if (!validate_closing_tags) {
                self.i += 2; // </
                const gt = scanner.findByte(self.input, self.i, '>') orelse {
                    self.i = self.input.len;
                    return;
                };
                self.i = gt + 1;
                if (self.doc.parse_stack.items.len > 1) self.finishNode(self.popStack());
                return;
            }

            self.i += 2; // </

            if (self.i < self.input.len and tables.isWhitespace(self.input[self.i])) {
                self.skipWhitespace();
            }
            if (self.i >= self.input.len) {
                if (strict_mode) return error.UnexpectedEndOfData;
                return;
            }

            if (!tables.isNameStart(self.input[self.i])) {
                if (validate_closing_tags) return error.InvalidClosingTagName;
                self.i = scanner.findByte(self.input, self.i, '>') orelse self.input.len;
                if (self.i < self.input.len) self.i += 1;
                return;
            }

            if (self.doc.parse_stack.items.len <= 1) {
                if (validate_closing_tags) return error.InvalidClosingTagName;
                return;
            }

            const close_start = self.i;
            const scan = scanNameAndKey(self.input, self.i);
            self.i = scan.end;
            const close_end = scan.end;
            const close_len = scan.len;
            const close_key = scan.key;

            const top = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1];
            if (top.tag_len == close_len and top.tag_key == close_key) {
                if (close_len > 8) {
                    const open_name = self.doc.nodes.items[top.idx].name.slice(self.input);
                    if (!std.mem.eql(u8, open_name[8..], self.input[close_start + 8 .. close_end])) {
                        return error.InvalidClosingTagName;
                    }
                }

                if (self.i >= self.input.len) {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    return error.InvalidClosingTagName;
                }
                if (self.input[self.i] == '>') {
                    self.i += 1;
                    self.finishNode(self.popStack());
                    return;
                }
                if (tables.isWhitespace(self.input[self.i])) {
                    self.skipWhitespace();
                    if (self.i >= self.input.len) {
                        if (strict_mode) return error.UnexpectedEndOfData;
                        return error.InvalidClosingTagName;
                    }
                    if (self.input[self.i] == '>') {
                        self.i += 1;
                        self.finishNode(self.popStack());
                        return;
                    }
                }
            }

            return error.InvalidClosingTagName;
        }

        fn parsePiOrDeclaration(noalias self: *Self) ParseError!void {
            self.i += 2; // <?

            if (self.i >= self.input.len or !tables.isNameStart(self.input[self.i])) {
                if (strict_mode) return error.ExpectedPiTarget;
                self.i = blk: {
                    var j = self.i;
                    while (true) {
                        const q = scanner.findByte(self.input, j, '?') orelse break :blk self.input.len;
                        if (q + 1 < self.input.len and self.input[q + 1] == '>') break :blk q;
                        j = q + 1;
                    }
                };
                if (self.i < self.input.len) self.i += 2;
                return;
            }

            const target_start = self.i;
            self.i += 1;
            self.i = scanner.findNameEnd(self.input, self.i);
            const target_end = self.i;

            self.skipWhitespace();
            const value_start = self.i;

            const end = blk: {
                var j = self.i;
                while (true) {
                    const q = scanner.findByte(self.input, j, '?') orelse break :blk null;
                    if (q + 1 < self.input.len and self.input[q + 1] == '>') break :blk q;
                    j = q + 1;
                }
            } orelse {
                if (strict_mode) return error.UnexpectedEndOfData;
                self.i = self.input.len;
                return;
            };
            const value_end = end;
            self.i = end + 2;

            if (!opts.include_misc_nodes) return;

            const decl = target_end - target_start == 3 and
                ((self.input[target_start] | 0x20) == 'x') and
                ((self.input[target_start + 1] | 0x20) == 'm') and
                ((self.input[target_start + 2] | 0x20) == 'l');
            const kind: NodeType = if (decl) .declaration else .pi;

            const parent_idx = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1].idx;
            const idx = try self.appendChildNodeTo(parent_idx, kind);
            var n = &self.doc.nodes.items[idx];
            n.name = .{ .start = @intCast(target_start), .end = @intCast(target_end) };
            n.value = .{ .start = @intCast(value_start), .end = @intCast(value_end) };
        }

        fn parseBangNode(noalias self: *Self) ParseError!void {
            if (self.i + 3 < self.input.len and self.input[self.i + 2] == '-' and self.input[self.i + 3] == '-') {
                const value_start = self.i + 4;
                const end = scanner.findSequence(self.input, value_start, "-->") orelse {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    self.i = self.input.len;
                    return;
                };
                self.i = end + 3;

                if (!opts.include_misc_nodes) return;

                const parent_idx = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1].idx;
                const idx = try self.appendChildNodeTo(parent_idx, .comment);
                var n = &self.doc.nodes.items[idx];
                n.value = .{ .start = @intCast(value_start), .end = @intCast(end) };
                return;
            }

            if (self.i + 8 < self.input.len and
                self.input[self.i + 2] == '[' and
                self.input[self.i + 3] == 'C' and
                self.input[self.i + 4] == 'D' and
                self.input[self.i + 5] == 'A' and
                self.input[self.i + 6] == 'T' and
                self.input[self.i + 7] == 'A' and
                self.input[self.i + 8] == '[')
            {
                const value_start = self.i + 9;
                const end = scanner.findSequence(self.input, value_start, "]]>") orelse {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    self.i = self.input.len;
                    return;
                };
                self.i = end + 3;

                if (!opts.include_misc_nodes) return;

                const parent_idx = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1].idx;
                const idx = try self.appendChildNodeTo(parent_idx, .cdata);
                var n = &self.doc.nodes.items[idx];
                n.value = .{ .start = @intCast(value_start), .end = @intCast(end) };
                return;
            }

            if (self.i + 9 <= self.input.len and
                self.input[self.i] == '<' and
                self.input[self.i + 1] == '!' and
                ((self.input[self.i + 2] | 0x20) == 'd') and
                ((self.input[self.i + 3] | 0x20) == 'o') and
                ((self.input[self.i + 4] | 0x20) == 'c') and
                ((self.input[self.i + 5] | 0x20) == 't') and
                ((self.input[self.i + 6] | 0x20) == 'y') and
                ((self.input[self.i + 7] | 0x20) == 'p') and
                ((self.input[self.i + 8] | 0x20) == 'e'))
            {
                var j = self.i + 9;
                var bracket_depth: i32 = 0;
                var quote: u8 = 0;

                while (j < self.input.len) : (j += 1) {
                    const c = self.input[j];
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

                    if (c == '>' and bracket_depth == 0) break;
                }

                if (j >= self.input.len) {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    self.i = self.input.len;
                    return;
                }

                const value_start = self.i + 9;
                const value_end = j;
                self.i = j + 1;

                if (expand_dtd_entities) {
                    try self.doc.registerDoctypeEntities(self.input[value_start..value_end]);
                }

                if (!opts.include_misc_nodes) return;

                const parent_idx = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1].idx;
                const idx = try self.appendChildNodeTo(parent_idx, .doctype);
                var n = &self.doc.nodes.items[idx];
                n.value = .{ .start = @intCast(value_start), .end = @intCast(value_end) };
                return;
            }

            if (strict_mode) return error.ExpectedGt;
            self.i = scanner.findByte(self.input, self.i, '>') orelse self.input.len;
            if (self.i < self.input.len) self.i += 1;
        }

        inline fn appendElementNodeTo(noalias self: *Self, parent_idx: IndexInt, name_start: usize, name_end: usize) ParseError!IndexInt {
            const len = self.doc.nodes.items.len;
            if (len == self.doc.nodes.capacity) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len + len / 2 + @as(usize, 8)) catch return error.OutOfMemory;
            }

            var parent = &self.doc.nodes.items[parent_idx];
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = .{
                .kind = .element,
                .name = .{ .start = @intCast(name_start), .end = @intCast(name_end) },
                .parent = parent_idx,
                .prev_sibling = parent.last_child,
                .subtree_end = idx,
            };
            parent.last_child = idx;
            return idx;
        }

        inline fn appendTextNodeTo(noalias self: *Self, parent_idx: IndexInt, start: usize, end: usize) ParseError!IndexInt {
            const len = self.doc.nodes.items.len;
            if (len == self.doc.nodes.capacity) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len + len / 2 + @as(usize, 8)) catch return error.OutOfMemory;
            }

            var parent = &self.doc.nodes.items[parent_idx];
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = .{
                .kind = .text,
                .value = .{ .start = @intCast(start), .end = @intCast(end) },
                .parent = parent_idx,
                .prev_sibling = parent.last_child,
                .subtree_end = idx,
            };
            parent.last_child = idx;
            return idx;
        }

        inline fn appendChildNodeTo(noalias self: *Self, parent_idx: IndexInt, kind: NodeType) ParseError!IndexInt {
            const len = self.doc.nodes.items.len;
            if (len == self.doc.nodes.capacity) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len + len / 2 + @as(usize, 8)) catch return error.OutOfMemory;
            }

            var parent = &self.doc.nodes.items[parent_idx];
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = .{
                .kind = kind,
                .parent = parent_idx,
                .prev_sibling = parent.last_child,
                .subtree_end = idx,
            };
            parent.last_child = idx;
            return idx;
        }

        inline fn pushStack(noalias self: *Self, idx: IndexInt, tag_key: u64, tag_len: u16) ParseError!void {
            const len = self.doc.parse_stack.items.len;
            if (len == self.doc.parse_stack.capacity) {
                @branchHint(.unlikely);
                self.doc.parse_stack.ensureTotalCapacityPrecise(self.doc.allocator, len + len / 2 + @as(usize, 8)) catch return error.OutOfMemory;
            }
            const out = self.doc.parse_stack.addOneAssumeCapacity();
            out.* = .{
                .idx = idx,
                .tag_key = tag_key,
                .tag_len = tag_len,
            };
        }

        inline fn popStack(noalias self: *Self) IndexInt {
            const top_idx = self.doc.parse_stack.items.len - 1;
            const idx = self.doc.parse_stack.items[top_idx].idx;
            self.doc.parse_stack.items.len = top_idx;
            return idx;
        }

        inline fn finishNode(noalias self: *Self, idx: IndexInt) void {
            self.doc.nodes.items[idx].subtree_end = @intCast(self.doc.nodes.items.len - 1);
        }

        inline fn skipWhitespace(noalias self: *Self) void {
            if (self.i >= self.input.len) return;
            const c = self.input[self.i];
            if (c == ' ') {
                const next = self.i + 1;
                if (next >= self.input.len or self.input[next] != ' ') {
                    self.i = next;
                    return;
                }
            } else if (!tables.isWhitespace(c)) {
                return;
            }
            self.i = scanner.skipWhitespace(self.input, self.i);
        }

        inline fn skipDroppedWhitespaceText(noalias self: *Self) void {
            if (!drop_whitespace_text_nodes) return;
            if (self.i >= self.input.len or !tables.WhitespaceTable[self.input[self.i]]) return;
            const next = scanner.skipWhitespace(self.input, self.i);
            if (next < self.input.len and self.input[next] == '<') {
                self.i = next;
            }
        }

        inline fn tryFinishSimpleTextElement(
            noalias self: *Self,
            idx: IndexInt,
            name_start: usize,
            tag_len: u16,
            tag_key: u64,
        ) ParseError!bool {
            // Fast-path the common `<tag>text</tag>` shape to avoid pushing a
            // stack frame only to immediately pop it again on the closing tag.
            const text_start = self.i;
            if (text_start >= self.input.len or self.input[text_start] == '<') return false;

            const lt = scanner.findByte(self.input, text_start, '<') orelse return false;
            if (lt == text_start or lt + 2 >= self.input.len or self.input[lt + 1] != '/') return false;

            const close_start = lt + 2;
            const close_end = close_start + tag_len;
            if (close_end > self.input.len) return false;
            const close_key = prefixKey(self.input[close_start..close_end]);
            if (tag_key != close_key) return false;
            const name_end = name_start + tag_len;
            if (tag_len > 8 and !std.mem.eql(u8, self.input[name_start + 8 .. name_end], self.input[close_start + 8 .. close_end])) {
                return false;
            }

            var j = close_end;
            if (j >= self.input.len) {
                if (strict_mode) return error.UnexpectedEndOfData;
                return false;
            }
            if (self.input[j] == '>') {
                self.i = j + 1;
            } else if (tables.isWhitespace(self.input[j])) {
                j += 1;
                while (j < self.input.len and tables.isWhitespace(self.input[j])) : (j += 1) {}
                if (j >= self.input.len) {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    return false;
                }
                if (self.input[j] != '>') return false;
                self.i = j + 1;
            } else {
                return false;
            }

            const raw = self.input[text_start..lt];
            if (drop_whitespace_text_nodes and tables.isWhitespace(raw[0])) {
                const whitespace_only = blk: {
                    if (!tables.isWhitespace(raw[raw.len - 1])) break :blk false;
                    if (raw.len == 1) break :blk true;

                    var i: usize = 1;
                    while (i + 1 < raw.len) : (i += 1) {
                        if (!tables.isWhitespace(raw[i])) break :blk false;
                    }
                    break :blk true;
                };
                if (whitespace_only) return true;
            }
            const text_idx = try self.appendTextNodeTo(idx, text_start, lt);
            self.doc.nodes.items[idx].subtree_end = text_idx;
            return true;
        }

        const NameScan = struct {
            end: usize,
            len: u16,
            /// Prefix fingerprint used as a fast reject for close-tag matching.
            key: u64,
        };

        inline fn prefixKey(input: []const u8) u64 {
            return switch (input.len) {
                0 => 0,
                1 => @as(u64, input[0]),
                2 => @as(u64, input[0]) |
                    (@as(u64, input[1]) << 8),
                3 => @as(u64, input[0]) |
                    (@as(u64, input[1]) << 8) |
                    (@as(u64, input[2]) << 16),
                4 => @as(u64, std.mem.readInt(u32, input[0..4], .little)),
                5 => @as(u64, std.mem.readInt(u32, input[0..4], .little)) |
                    (@as(u64, input[4]) << 32),
                6 => @as(u64, std.mem.readInt(u32, input[0..4], .little)) |
                    (@as(u64, input[4]) << 32) |
                    (@as(u64, input[5]) << 40),
                7 => @as(u64, std.mem.readInt(u32, input[0..4], .little)) |
                    (@as(u64, input[4]) << 32) |
                    (@as(u64, input[5]) << 40) |
                    (@as(u64, input[6]) << 48),
                else => std.mem.readInt(u64, input[0..8], .little),
            };
        }

        inline fn scanNameAndKey(input: []const u8, start: usize) NameScan {
            // Cache the leading bytes alongside the span length so closing-tag
            // checks usually avoid a full string compare.
            var i = start;
            var key: u64 = 0;
            inline for (0..8) |n| {
                if (i >= input.len or !tables.isNameChar(input[i])) {
                    return .{
                        .end = i,
                        .len = @intCast(i - start),
                        .key = key,
                    };
                }
                key |= @as(u64, input[i]) << @as(std.math.Log2Int(u64), n * 8);
                i += 1;
            }
            while (i < input.len and tables.isNameChar(input[i])) : (i += 1) {}
            return .{
                .end = i,
                .len = @intCast(i - start),
                .key = key,
            };
        }
    };
}

test "parseInto builds a minimal DOM and enforces strict closing tags" {
    const options: ParseOptions = .{};
    const Document = document.Types(options).Document;
    var ok = "<root><child>v</child></root>".*;
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    doc.source = &ok;
    try parseInto(&doc, &ok, .{ .mode = .strict, .validate_closing_tags = true });
    try std.testing.expectEqual(@as(usize, 4), doc.nodes.items.len);
    try std.testing.expectEqualStrings("root", doc.nodeAt(1).?.nameSlice());
    try std.testing.expectEqualStrings("child", doc.nodeAt(2).?.nameSlice());
    try std.testing.expectEqualStrings("v", doc.nodeAt(3).?.valueRawSlice());

    var bad = "<root><child></root>".*;
    doc.clear();
    doc.source = &bad;
    try std.testing.expectError(
        error.InvalidClosingTagName,
        parseInto(&doc, &bad, .{ .mode = .strict, .validate_closing_tags = true }),
    );
}
