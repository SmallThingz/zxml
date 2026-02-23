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

pub fn parseInto(noalias doc: *Document, noalias input: []u8, comptime opts: ParseOptions) ParseError!void {
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

        fn parse(noalias self: *Self) ParseError!void {
            try self.doc.reserveForInput(self.input.len);
            _ = try self.appendNodeRaw(.document, InvalidIndex);
            try self.pushStack(0);

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

            while (self.doc.parse_stack.items.len > 0) {
                _ = self.popStack();
            }
        }

        inline fn parseTextRange(noalias self: *Self, start: usize, end: usize) ParseError!void {
            if (end <= start) return;

            if (!decode_entities and !normalize_text) {
                const raw = self.input[start..end];
                if (isWhitespaceOnlyFast(raw)) return;

                const idx_fast = try self.appendChildNode(.text);
                var n_fast = &self.doc.nodes.items[idx_fast];
                n_fast.value = .{ .start = @intCast(start), .end = @intCast(end) };
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

            const idx = try self.appendChildNode(.text);
            var n = &self.doc.nodes.items[idx];
            n.value = .{ .start = @intCast(start), .end = @intCast(start + text_len) };
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
            self.i = scanner.findNameEnd(self.input, self.i);
            const name_end = self.i;

            const idx = try self.appendChildNode(.element);
            var node = &self.doc.nodes.items[idx];
            node.name = .{ .start = @intCast(name_start), .end = @intCast(name_end) };

            const attr_start_idx: u32 = @intCast(self.doc.attrs.items.len);

            // Common path: start tag with no attributes.
            if (self.i < self.input.len) {
                const c0 = self.input[self.i];
                if (c0 == '>') {
                    self.i += 1;
                    node = &self.doc.nodes.items[idx];
                    node.attr_start = attr_start_idx;
                    node.attr_len = 0;
                    try self.pushStack(idx);
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
                    node.attr_len = @intCast(self.doc.attrs.items.len - attr_start_idx);
                    try self.pushStack(idx);
                    return;
                }

                if (c == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    self.i += 2;
                    node = &self.doc.nodes.items[idx];
                    node.attr_start = attr_start_idx;
                    node.attr_len = @intCast(self.doc.attrs.items.len - attr_start_idx);
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
                    if (scanner.findByte(self.input, self.i, quote)) |quote_pos| {
                        value_end = quote_pos;
                        self.i = quote_pos + 1;
                    } else {
                        if (strict_mode) return error.ExpectedQuote;
                        value_end = self.input.len;
                        self.i = self.input.len;
                    }
                } else {
                    if (strict_mode) return error.ExpectedQuote;
                    value_start = self.i;
                    self.i = scanner.findAttrUnquotedEnd(self.input, self.i);
                    value_end = self.i;
                }
            }

            var final_value_end = value_end;
            if (decode_entities and value_end >= value_start) {
                const value = self.input[value_start..value_end];
                const decoded_len = entities.decodeInPlaceIfEntity(value, strict_mode) catch |e| switch (e) {
                    error.InvalidNumericCharacterEntity => return error.InvalidNumericCharacterEntity,
                    error.UnterminatedEntity => return error.UnterminatedEntity,
                };
                final_value_end = value_start + decoded_len;
            }

            try self.appendAttributeRaw(.{
                .start = @intCast(name_start),
                .end = @intCast(name_end),
            }, .{
                .start = @intCast(value_start),
                .end = @intCast(final_value_end),
            });
        }

        inline fn parseClosingTag(noalias self: *Self) ParseError!void {
            if (!strict_mode and !opts.validate_closing_tags) {
                return self.parseClosingTagTurbo();
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
                if (strict_or_validate) return error.InvalidClosingTagName;
                self.i = scanner.findByte(self.input, self.i, '>') orelse self.input.len;
                if (self.i < self.input.len) self.i += 1;
                return;
            }

            if (self.doc.parse_stack.items.len <= 1) {
                if (strict_or_validate) return error.InvalidClosingTagName;
                return;
            }

            const top_idx = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1].idx;
            const top = &self.doc.nodes.items[top_idx];
            const top_name = top.name.slice(self.input);

            if (self.i + top_name.len <= self.input.len and std.mem.eql(u8, self.input[self.i .. self.i + top_name.len], top_name)) {
                self.i += top_name.len;
                if (self.i >= self.input.len) {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    return error.InvalidClosingTagName;
                }
                if (self.i < self.input.len and self.input[self.i] == '>') {
                    self.i += 1;
                    _ = self.popStack();
                    return;
                }
                if (self.i < self.input.len and tables.isWhitespace(self.input[self.i])) {
                    self.skipWhitespace();
                    if (self.i >= self.input.len) {
                        if (strict_mode) return error.UnexpectedEndOfData;
                        return error.InvalidClosingTagName;
                    }
                    if (self.i < self.input.len and self.input[self.i] == '>') {
                        self.i += 1;
                        _ = self.popStack();
                        return;
                    }
                }
            }

            return error.InvalidClosingTagName;
        }

        inline fn parseClosingTagTurbo(noalias self: *Self) ParseError!void {
            self.i += 2; // </

            if (self.doc.parse_stack.items.len > 1 and self.i < self.input.len and tables.isNameStart(self.input[self.i])) {
                const top_idx = self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1].idx;
                const top_name = self.doc.nodes.items[top_idx].name.slice(self.input);

                if (self.i + top_name.len <= self.input.len and std.mem.eql(u8, self.input[self.i .. self.i + top_name.len], top_name)) {
                    self.i += top_name.len;
                    if (self.i < self.input.len and self.input[self.i] == '>') {
                        self.i += 1;
                        _ = self.popStack();
                        return;
                    }
                    if (self.i < self.input.len and tables.isWhitespace(self.input[self.i])) {
                        self.skipWhitespace();
                        if (self.i < self.input.len and self.input[self.i] == '>') {
                            self.i += 1;
                            _ = self.popStack();
                            return;
                        }
                    }
                }
            }

            const gt = scanner.findByte(self.input, self.i, '>') orelse {
                self.i = self.input.len;
                return;
            };
            self.i = gt + 1;
            if (self.doc.parse_stack.items.len > 1) _ = self.popStack();
        }

        fn parsePiOrDeclaration(noalias self: *Self) ParseError!void {
            self.i += 2; // <?

            if (self.i >= self.input.len or !tables.isNameStart(self.input[self.i])) {
                if (strict_mode) return error.ExpectedPiTarget;
                self.i = scanner.findSequence(self.input, self.i, "?>") orelse self.input.len;
                if (self.i < self.input.len) self.i += 2;
                return;
            }

            const target_start = self.i;
            self.i += 1;
            self.i = scanner.findNameEnd(self.input, self.i);
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

            const idx = try self.appendChildNode(kind);
            var n = &self.doc.nodes.items[idx];
            n.name = .{ .start = @intCast(target_start), .end = @intCast(target_end) };
            n.value = .{ .start = @intCast(value_start), .end = @intCast(value_end) };
        }

        fn parseBangNode(noalias self: *Self) ParseError!void {
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

        fn parseComment(noalias self: *Self) ParseError!void {
            const value_start = self.i + 4;
            const end = scanner.findSequence(self.input, value_start, "-->") orelse {
                if (strict_mode) return error.UnexpectedEndOfData;
                self.i = self.input.len;
                return;
            };
            self.i = end + 3;

            if (!opts.include_misc_nodes) return;

            const idx = try self.appendChildNode(.comment);
            var n = &self.doc.nodes.items[idx];
            n.value = .{ .start = @intCast(value_start), .end = @intCast(end) };
        }

        fn parseCdata(noalias self: *Self) ParseError!void {
            const value_start = self.i + 9;
            const end = scanner.findSequence(self.input, value_start, "]]>") orelse {
                if (strict_mode) return error.UnexpectedEndOfData;
                self.i = self.input.len;
                return;
            };
            self.i = end + 3;

            if (!opts.include_misc_nodes) return;

            const idx = try self.appendChildNode(.cdata);
            var n = &self.doc.nodes.items[idx];
            n.value = .{ .start = @intCast(value_start), .end = @intCast(end) };
        }

        fn parseDoctype(noalias self: *Self) ParseError!void {
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

            const idx = try self.appendChildNode(.doctype);
            var n = &self.doc.nodes.items[idx];
            n.value = .{ .start = @intCast(value_start), .end = @intCast(value_end) };
        }

        fn hasDoctypePrefix(noalias self: *const Self) bool {
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

        inline fn currentParent(noalias self: *const Self) u32 {
            return self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1].idx;
        }

        inline fn appendChildNode(noalias self: *Self, kind: NodeType) ParseError!u32 {
            const parent_idx = self.currentParent();
            const idx = try self.appendNodeRaw(kind, parent_idx);
            self.linkToCurrentParent(idx);
            return idx;
        }

        inline fn appendNodeRaw(noalias self: *Self, kind: NodeType, parent_idx: u32) ParseError!u32 {
            if (self.doc.nodes.items.len == self.doc.nodes.capacity) {
                self.doc.nodes.ensureUnusedCapacity(self.doc.allocator, 8) catch return error.OutOfMemory;
            }

            const idx: u32 = @intCast(self.doc.nodes.items.len);
            const at = self.doc.nodes.items.len;
            self.doc.nodes.items.len = at + 1;
            if (comptime opts.store_parent_pointers) {
                self.doc.nodes.items[at] = .{
                    .doc = self.doc,
                    .kind = kind,
                    .parent = parent_idx,
                };
            } else {
                self.doc.nodes.items[at] = .{
                    .doc = self.doc,
                    .kind = kind,
                };
            }
            return idx;
        }

        inline fn appendAttributeRaw(noalias self: *Self, name: Span, value: Span) ParseError!void {
            if (self.doc.attrs.items.len == self.doc.attrs.capacity) {
                self.doc.attrs.ensureUnusedCapacity(self.doc.allocator, 8) catch return error.OutOfMemory;
            }
            const at = self.doc.attrs.items.len;
            self.doc.attrs.items.len = at + 1;
            self.doc.attrs.items[at] = .{
                .doc = self.doc,
                .name = name,
                .value = value,
            };
        }

        inline fn linkToCurrentParent(noalias self: *Self, child_idx: u32) void {
            var parent_entry = &self.doc.parse_stack.items[self.doc.parse_stack.items.len - 1];
            const last = parent_entry.last_child;
            if (last == InvalidIndex) {
                parent_entry.first_child = child_idx;
            } else {
                self.doc.nodes.items[last].next_sibling = child_idx;
            }
            parent_entry.last_child = child_idx;
        }

        inline fn pushStack(noalias self: *Self, idx: u32) ParseError!void {
            if (self.doc.parse_stack.items.len == self.doc.parse_stack.capacity) {
                self.doc.parse_stack.ensureUnusedCapacity(self.doc.allocator, 8) catch return error.OutOfMemory;
            }
            const at = self.doc.parse_stack.items.len;
            self.doc.parse_stack.items.len = at + 1;
            self.doc.parse_stack.items[at] = .{ .idx = idx };
        }

        inline fn popStack(noalias self: *Self) u32 {
            const old_len = self.doc.parse_stack.items.len;
            const top_idx = old_len - 1;
            const entry = self.doc.parse_stack.items[top_idx];
            self.doc.parse_stack.items.len = top_idx;

            if (entry.first_child != InvalidIndex) {
                var node = &self.doc.nodes.items[entry.idx];
                node.first_child = entry.first_child;
                node.last_child = entry.last_child;
            }
            return entry.idx;
        }

        inline fn skipWhitespace(noalias self: *Self) void {
            if (self.i >= self.input.len or !tables.isWhitespace(self.input[self.i])) return;
            while (self.i < self.input.len and tables.isWhitespace(self.input[self.i])) : (self.i += 1) {}
        }

        fn isWhitespaceOnlyFast(bytes: []const u8) bool {
            if (bytes.len == 0) return true;
            if (!tables.isWhitespace(bytes[0])) return false;
            if (!tables.isWhitespace(bytes[bytes.len - 1])) return false;
            if (bytes.len == 1) return true;

            var i: usize = 1;
            while (i + 1 < bytes.len) : (i += 1) {
                if (!tables.isWhitespace(bytes[i])) return false;
            }
            return true;
        }
    };
}
