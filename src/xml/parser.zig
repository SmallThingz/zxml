const std = @import("std");
const document = @import("document.zig");
const scanner = @import("scanner.zig");
const tables = @import("tables.zig");
const entities = @import("entities.zig");

const Document = document.Document;
const ParseOptions = document.ParseOptions;
const ParseMode = document.ParseMode;
const ParseError = document.ParseError;
const NodeType = document.NodeType;
const Span = document.Span;
const InvalidIndex = document.InvalidIndex;

pub fn parseInto(doc: *Document, input: []u8, comptime opts: ParseOptions) ParseError!void {
    var p = Parser(opts){ .doc = doc, .input = input, .i = 0 };
    try p.parse();
}

fn Parser(comptime opts: ParseOptions) type {
    return struct {
        doc: *Document,
        input: []u8,
        i: usize,

        const Self = @This();

        const strict_mode = opts.mode == .strict;
        const strict_or_validate = strict_mode or opts.validate_closing_tags;
        const decode_entities = opts.decode_entities_on_parse;
        const normalize_text = opts.normalize_text_whitespace;

        fn parse(self: *Self) ParseError!void {
            try self.doc.reserveForInput(self.input.len);
            _ = try self.doc.appendNode(.document, InvalidIndex, false);
            try self.doc.parse_stack.append(self.doc.allocator, 0);

            while (self.i < self.input.len) {
                if (self.input[self.i] != '<') {
                    const lt = scanner.findByte(self.input, self.i, '<') orelse {
                        try self.parseTextRange(self.i, self.input.len);
                        self.i = self.input.len;
                        break;
                    };
                    try self.parseTextRange(self.i, lt);
                    self.i = lt;
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

            if (strict_mode and self.doc.parse_stack.items.len > 1) {
                return error.UnexpectedEndOfData;
            }

            const end: u32 = @intCast(self.input.len);
            while (self.doc.parse_stack.items.len > 1) {
                const idx = self.doc.parse_stack.pop().?;
                self.closeNode(idx, end, end);
            }

            self.doc.nodes.items[0].subtree_end = if (self.doc.nodes.items.len == 0) 0 else @intCast(self.doc.nodes.items.len - 1);
            self.doc.parse_stack.clearRetainingCapacity();
        }

        fn parseTextRange(self: *Self, start: usize, end: usize) ParseError!void {
            if (end <= start) return;

            if (!decode_entities and !normalize_text) {
                const parent_fast = self.currentParent();
                const idx_fast = try self.doc.appendNode(.text, parent_fast, opts.store_parent_pointers);
                var n_fast = &self.doc.nodes.items[idx_fast];
                n_fast.value = .{ .start = @intCast(start), .end = @intCast(end) };
                n_fast.subtree_end = idx_fast;
                return;
            }

            const text = self.input[start..end];
            var text_len: usize = text.len;

            if (decode_entities and normalize_text) {
                text_len = entities.decodeAndNormalizeInPlace(text, strict_mode) catch |e| switch (e) {
                    error.InvalidNumericCharacterEntity => return error.InvalidNumericCharacterEntity,
                    error.UnterminatedEntity => return error.UnterminatedEntity,
                };
            } else if (decode_entities) {
                text_len = entities.decodeInPlaceIfEntity(text, strict_mode) catch |e| switch (e) {
                    error.InvalidNumericCharacterEntity => return error.InvalidNumericCharacterEntity,
                    error.UnterminatedEntity => return error.UnterminatedEntity,
                };
            } else if (normalize_text) {
                text_len = entities.normalizeWhitespaceInPlace(text);
            }

            if (text_len == 0) return;

            const parent = self.currentParent();
            const idx = try self.doc.appendNode(.text, parent, opts.store_parent_pointers);
            var n = &self.doc.nodes.items[idx];
            n.value = .{ .start = @intCast(start), .end = @intCast(start + text_len) };
            n.subtree_end = idx;
        }

        fn parseOpeningTag(self: *Self) ParseError!void {
            const open_start = self.i;
            self.i += 1; // '<'

            if (self.i >= self.input.len) return error.UnexpectedEndOfData;
            if (!tables.isNameStart(self.input[self.i])) {
                if (strict_mode) return error.ExpectedElementName;
                self.i = (scanner.findByte(self.input, self.i, '>') orelse self.input.len);
                if (self.i < self.input.len) self.i += 1;
                return;
            }

            const name_start = self.i;
            while (self.i < self.input.len and tables.isNameChar(self.input[self.i])) : (self.i += 1) {}
            const name_end = self.i;

            const parent = self.currentParent();
            const idx = try self.doc.appendNode(.element, parent, opts.store_parent_pointers);
            var node = &self.doc.nodes.items[idx];
            node.open_start = @intCast(open_start);
            node.name = .{ .start = @intCast(name_start), .end = @intCast(name_end) };

            const attr_start_idx: u32 = @intCast(self.doc.attrs.items.len);

            while (self.i < self.input.len) {
                self.skipWhitespace();
                if (self.i >= self.input.len) return error.UnexpectedEndOfData;

                const c = self.input[self.i];
                if (c == '>') {
                    self.i += 1;
                    node = &self.doc.nodes.items[idx];
                    node.open_end = @intCast(self.i);
                    node.attr_start = attr_start_idx;
                    node.attr_len = @intCast(self.doc.attrs.items.len - attr_start_idx);
                    try self.doc.parse_stack.append(self.doc.allocator, idx);
                    return;
                }

                if (c == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    self.i += 2;
                    node = &self.doc.nodes.items[idx];
                    node.open_end = @intCast(self.i);
                    node.close_start = @intCast(self.i);
                    node.close_end = @intCast(self.i);
                    node.subtree_end = idx;
                    node.attr_start = attr_start_idx;
                    node.attr_len = @intCast(self.doc.attrs.items.len - attr_start_idx);
                    return;
                }

                try self.parseAttribute(idx);
            }

            return error.UnexpectedEndOfData;
        }

        fn parseAttribute(self: *Self, node_idx: u32) ParseError!void {
            if (self.i >= self.input.len) return error.UnexpectedEndOfData;

            if (!tables.isNameStart(self.input[self.i])) {
                self.i += 1;
                return;
            }

            const name_start = self.i;
            while (self.i < self.input.len and tables.isNameChar(self.input[self.i])) : (self.i += 1) {}
            const name_end = self.i;

            self.skipWhitespace();

            var value_start = self.i;
            var value_end = self.i;

            if (self.i < self.input.len and self.input[self.i] == '=') {
                self.i += 1;
                self.skipWhitespace();

                if (self.i >= self.input.len) return error.UnexpectedEndOfData;

                const c = self.input[self.i];
                if (c == '\'' or c == '"') {
                    const quote = c;
                    self.i += 1;
                    value_start = self.i;
                    const quote_pos = scanner.findByte(self.input, self.i, quote) orelse {
                        if (strict_mode) return error.ExpectedQuote;
                        value_end = self.input.len;
                        self.i = self.input.len;
                        try self.finalizeAttribute(node_idx, name_start, name_end, value_start, value_end);
                        return;
                    };
                    value_end = quote_pos;
                    self.i = quote_pos + 1;
                } else {
                    if (strict_mode) return error.ExpectedQuote;
                    value_start = self.i;
                    while (self.i < self.input.len and tables.isAttrUnquotedValueChar(self.input[self.i])) : (self.i += 1) {}
                    value_end = self.i;
                }
            }

            try self.finalizeAttribute(node_idx, name_start, name_end, value_start, value_end);
        }

        fn finalizeAttribute(self: *Self, node_idx: u32, name_start: usize, name_end: usize, value_start: usize, value_end: usize) ParseError!void {
            var final_value_end = value_end;
            if (decode_entities and value_end >= value_start) {
                const value = self.input[value_start..value_end];
                const decoded_len = entities.decodeInPlaceIfEntity(value, strict_mode) catch |e| switch (e) {
                    error.InvalidNumericCharacterEntity => return error.InvalidNumericCharacterEntity,
                    error.UnterminatedEntity => return error.UnterminatedEntity,
                };
                final_value_end = value_start + decoded_len;
            }

            _ = try self.doc.appendAttribute(node_idx, .{
                .start = @intCast(name_start),
                .end = @intCast(name_end),
            }, .{
                .start = @intCast(value_start),
                .end = @intCast(final_value_end),
            });
        }

        fn parseClosingTag(self: *Self) ParseError!void {
            if (!strict_mode and !opts.validate_closing_tags) {
                return self.parseClosingTagTurbo();
            }

            const close_start = self.i;
            self.i += 2; // </

            self.skipWhitespace();
            if (self.i >= self.input.len) return error.UnexpectedEndOfData;

            if (!tables.isNameStart(self.input[self.i])) {
                if (strict_or_validate) return error.InvalidClosingTagName;
                self.i = scanner.findByte(self.input, self.i, '>') orelse self.input.len;
                if (self.i < self.input.len) self.i += 1;
                return;
            }

            const name_start = self.i;
            while (self.i < self.input.len and tables.isNameChar(self.input[self.i])) : (self.i += 1) {}
            const name_end = self.i;
            const close_name = self.input[name_start..name_end];

            const gt = scanner.findByte(self.input, self.i, '>') orelse {
                if (strict_mode) return error.UnexpectedEndOfData;
                self.i = self.input.len;
                return;
            };
            self.i = gt + 1;
            const close_end: u32 = @intCast(self.i);

            if (self.doc.parse_stack.items.len <= 1) {
                if (strict_or_validate) return error.InvalidClosingTagName;
                return;
            }

            const top_idx = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1];
            const top = &self.doc.nodes.items[top_idx];
            const top_name = top.name.slice(self.input);

            if (strict_or_validate) {
                if (top_name.len != close_name.len or !std.mem.eql(u8, top_name, close_name)) {
                    return error.InvalidClosingTagName;
                }
                _ = self.doc.parse_stack.pop();
                self.closeNode(top_idx, @intCast(close_start), close_end);
                return;
            }

            if (top_name.len == close_name.len and std.mem.eql(u8, top_name, close_name)) {
                _ = self.doc.parse_stack.pop();
                self.closeNode(top_idx, @intCast(close_start), close_end);
                return;
            }

            var pos_opt: ?usize = null;
            var s = self.doc.parse_stack.items.len;
            while (s > 1) {
                s -= 1;
                const idx = self.doc.parse_stack.items[s];
                const node = &self.doc.nodes.items[idx];
                const node_name = node.name.slice(self.input);
                if (node_name.len != close_name.len or !std.mem.eql(u8, node_name, close_name)) continue;
                pos_opt = s;
                break;
            }

            if (pos_opt) |pos| {
                while (self.doc.parse_stack.items.len > pos) {
                    const idx = self.doc.parse_stack.pop().?;
                    self.closeNode(idx, @intCast(close_start), close_end);
                }
            }
        }

        fn parseClosingTagTurbo(self: *Self) ParseError!void {
            const close_start = self.i;
            self.i += 2; // </

            const gt = scanner.findByte(self.input, self.i, '>') orelse {
                self.i = self.input.len;
                return;
            };
            self.i = gt + 1;
            const close_end: u32 = @intCast(self.i);

            if (self.doc.parse_stack.items.len <= 1) return;
            const idx = self.doc.parse_stack.pop().?;
            self.closeNode(idx, @intCast(close_start), close_end);
        }

        fn parsePiOrDeclaration(self: *Self) ParseError!void {
            const node_start = self.i;
            self.i += 2; // <?

            if (self.i >= self.input.len or !tables.isNameStart(self.input[self.i])) {
                if (strict_mode) return error.ExpectedPiTarget;
                self.i = scanner.findSequence(self.input, self.i, "?>") orelse self.input.len;
                if (self.i < self.input.len) self.i += 2;
                return;
            }

            const target_start = self.i;
            self.i += 1;
            while (self.i < self.input.len and tables.isNameChar(self.input[self.i])) : (self.i += 1) {}
            const target_end = self.i;

            self.skipWhitespace();
            const value_start = self.i;

            const end = scanner.findSequence(self.input, self.i, "?>") orelse {
                if (strict_mode) return error.UnexpectedEndOfData;
                self.i = self.input.len;
                return;
            };
            const value_end = end;
            self.i = end + 2;

            if (!opts.include_misc_nodes) return;

            const target = self.input[target_start..target_end];
            const decl = tables.eqlAsciiCaseInsensitive(target, "xml");
            const kind: NodeType = if (decl) .declaration else .pi;

            const parent = self.currentParent();
            const idx = try self.doc.appendNode(kind, parent, opts.store_parent_pointers);
            var n = &self.doc.nodes.items[idx];
            n.open_start = @intCast(node_start);
            n.open_end = @intCast(self.i);
            n.close_start = @intCast(self.i);
            n.close_end = @intCast(self.i);
            n.subtree_end = idx;
            n.name = .{ .start = @intCast(target_start), .end = @intCast(target_end) };
            n.value = .{ .start = @intCast(value_start), .end = @intCast(value_end) };
        }

        fn parseBangNode(self: *Self) ParseError!void {
            if (self.i + 3 < self.input.len and self.input[self.i + 2] == '-' and self.input[self.i + 3] == '-') {
                try self.parseComment();
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
                try self.parseCdata();
                return;
            }

            if (self.hasDoctypePrefix()) {
                try self.parseDoctype();
                return;
            }

            if (strict_mode) return error.ExpectedGt;
            self.i = scanner.findByte(self.input, self.i, '>') orelse self.input.len;
            if (self.i < self.input.len) self.i += 1;
        }

        fn parseComment(self: *Self) ParseError!void {
            const node_start = self.i;
            const value_start = self.i + 4;
            const end = scanner.findSequence(self.input, value_start, "-->") orelse {
                if (strict_mode) return error.UnexpectedEndOfData;
                self.i = self.input.len;
                return;
            };
            self.i = end + 3;

            if (!opts.include_misc_nodes) return;

            const parent = self.currentParent();
            const idx = try self.doc.appendNode(.comment, parent, opts.store_parent_pointers);
            var n = &self.doc.nodes.items[idx];
            n.open_start = @intCast(node_start);
            n.open_end = @intCast(self.i);
            n.close_start = @intCast(self.i);
            n.close_end = @intCast(self.i);
            n.value = .{ .start = @intCast(value_start), .end = @intCast(end) };
            n.subtree_end = idx;
        }

        fn parseCdata(self: *Self) ParseError!void {
            const node_start = self.i;
            const value_start = self.i + 9;
            const end = scanner.findSequence(self.input, value_start, "]]>") orelse {
                if (strict_mode) return error.UnexpectedEndOfData;
                self.i = self.input.len;
                return;
            };
            self.i = end + 3;

            if (!opts.include_misc_nodes) return;

            const parent = self.currentParent();
            const idx = try self.doc.appendNode(.cdata, parent, opts.store_parent_pointers);
            var n = &self.doc.nodes.items[idx];
            n.open_start = @intCast(node_start);
            n.open_end = @intCast(self.i);
            n.close_start = @intCast(self.i);
            n.close_end = @intCast(self.i);
            n.value = .{ .start = @intCast(value_start), .end = @intCast(end) };
            n.subtree_end = idx;
        }

        fn parseDoctype(self: *Self) ParseError!void {
            const node_start = self.i;
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

            if (!opts.include_misc_nodes) return;

            const parent = self.currentParent();
            const idx = try self.doc.appendNode(.doctype, parent, opts.store_parent_pointers);
            var n = &self.doc.nodes.items[idx];
            n.open_start = @intCast(node_start);
            n.open_end = @intCast(self.i);
            n.close_start = @intCast(self.i);
            n.close_end = @intCast(self.i);
            n.value = .{ .start = @intCast(value_start), .end = @intCast(value_end) };
            n.subtree_end = idx;
        }

        fn hasDoctypePrefix(self: *const Self) bool {
            if (self.i + 9 > self.input.len) return false;
            return self.input[self.i] == '<' and
                self.input[self.i + 1] == '!' and
                ((self.input[self.i + 2] | 0x20) == 'd') and
                ((self.input[self.i + 3] | 0x20) == 'o') and
                ((self.input[self.i + 4] | 0x20) == 'c') and
                ((self.input[self.i + 5] | 0x20) == 't') and
                ((self.input[self.i + 6] | 0x20) == 'y') and
                ((self.input[self.i + 7] | 0x20) == 'p') and
                ((self.input[self.i + 8] | 0x20) == 'e');
        }

        fn closeNode(self: *Self, idx: u32, close_start: u32, close_end: u32) void {
            var n = &self.doc.nodes.items[idx];
            n.close_start = close_start;
            n.close_end = close_end;
            n.subtree_end = @intCast(self.doc.nodes.items.len - 1);
        }

        fn currentParent(self: *const Self) u32 {
            if (self.doc.parse_stack.items.len == 0) return 0;
            return self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1];
        }

        fn skipWhitespace(self: *Self) void {
            while (self.i < self.input.len and tables.isWhitespace(self.input[self.i])) : (self.i += 1) {}
        }
    };
}
