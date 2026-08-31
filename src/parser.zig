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

inline fn attributeNameHash(name: []const u8) u64 {
    var mixed = scanner.prefixKey(name) ^ (@as(u64, name.len) << 56);
    mixed *%= 0x9e3779b97f4a7c15;
    mixed ^= mixed >> 32;
    return mixed;
}

noinline fn findDuplicateAttributeQuadratic(input: []const u8, attrs: []const document.RawAttribute) linksection(".text.unlikely.zxml") ?usize {
    @branchHint(.cold);
    if (attrs.len >= 32 and attrs.len <= 128) {
        @branchHint(.unlikely);
        return findDuplicateAttributeLarge(input, attrs);
    }
    for (attrs, 0..) |current, i| {
        const current_name = current.name.slice(input);
        for (attrs[0..i]) |previous| {
            if (std.mem.eql(u8, previous.name.slice(input), current_name)) return current.name.start;
        }
    }
    return null;
}

noinline fn findDuplicateAttributeLarge(input: []const u8, attrs: []const document.RawAttribute) linksection(".text.unlikely.zxml") ?usize {
    @branchHint(.cold);
    const table_capacity = 256;
    var slots: [table_capacity]u32 = undefined;
    var occupied = [_]u64{0} ** (table_capacity / 64);
    for (attrs, 0..) |attr, attr_index| {
        const name = attr.name.slice(input);
        const hash = attributeNameHash(name);
        const fingerprint: u32 = @truncate(hash);
        var slot_index: usize = @intCast(hash >> 56);
        while (true) {
            const word_index = slot_index >> 6;
            const bit = @as(u64, 1) << @as(u6, @intCast(slot_index & 63));
            if (occupied[word_index] & bit == 0) {
                slots[slot_index] = fingerprint;
                occupied[word_index] |= bit;
                break;
            }
            if (slots[slot_index] == fingerprint) {
                for (attrs[0..attr_index]) |previous| {
                    if (std.mem.eql(u8, previous.name.slice(input), name)) return attr.name.start;
                }
            }
            slot_index = (slot_index + 1) & (table_capacity - 1);
        }
    }
    return null;
}

noinline fn findDuplicateAttribute(input: []const u8, attrs: []const document.RawAttribute) align(128) ?usize {
    if (attrs.len >= 32 and attrs.len <= 128) {
        @branchHint(.unlikely);
        return findDuplicateAttributeLarge(input, attrs);
    }
    var buckets: u64 = 0;
    for (attrs) |attr| {
        const name = attr.name.slice(input);
        const hash = attributeNameHash(name);
        const bit = @as(u64, 1) << @as(u6, @intCast(hash >> 58));
        if (buckets & bit != 0) return findDuplicateAttributeQuadratic(input, attrs);
        buckets |= bit;
    }
    return null;
}

pub fn parseInto(noalias doc: anytype, input: []const u8, comptime opts: ParseOptions) ParseError!void {
    doc.last_error_offset = 0;
    if (!common.lenFits(input.len)) return error.InputTooLarge;
    if (comptime opts.mode == .strict) try document.validateXmlCharacters(input);
    var p = Parser(opts, @TypeOf(doc.*)){ .doc = doc, .input = input, .i = 0 };
    p.parse() catch |err| {
        doc.last_error_offset = @min(p.i, input.len);
        return err;
    };
}

fn Parser(comptime opts: ParseOptions, comptime DocType: type) type {
    return struct {
        doc: *DocType,
        input: []const u8,
        i: usize,
        current_parent: IndexInt = 0,
        root_seen: bool = false,
        doctype_seen: bool = false,
        standalone_yes: bool = false,
        doctype_value_start: usize = 0,
        doctype_value_end: usize = 0,
        require_declared_entities: bool = true,

        const Self = @This();

        const strict_mode = opts.mode == .strict;
        const validate_closing_tags = opts.validate_closing_tags;
        const require_closed_elements_on_eof = opts.require_closed_elements_on_eof;
        const expand_dtd_entities = opts.expand_dtd_entities;
        const drop_whitespace_text_nodes = opts.drop_whitespace_text_nodes;

        fn parse(noalias self: *Self) align(128) ParseError!void {
            try self.doc.reserveForInput(self.input.len);
            if (comptime validate_closing_tags) {
                try self.doc.parse_validate_stack.ensureTotalCapacity(self.doc.allocator, self.doc.parse_stack.capacity);
                std.debug.assert(self.doc.parse_validate_stack.items.len == 0);
            }
            std.debug.assert(self.doc.nodes.items.len == 0 and self.doc.attrs.items.len == 0);
            _ = self.doc.nodes.addOneAssumeCapacity();
            self.doc.nodes.items[0] = .{
                .kind = .document,
                .parent = InvalidIndex,
                .subtree_end = 0,
            };
            try self.pushStack(0, 0, 0);

            while (self.i < self.input.len) {
                if (self.input[self.i] != '<') {
                    if (comptime strict_mode) {
                        const text_start = self.i;
                        const whitespace_end = if (tables.WhitespaceTable[self.input[text_start]]) scanner.skipWhitespace(self.input, text_start) else text_start;
                        const has_non_whitespace = whitespace_end == text_start or (whitespace_end < self.input.len and self.input[whitespace_end] != '<');
                        const run = if (has_non_whitespace) scanner.scanTextSpecials(self.input, whitespace_end) else scanner.TextSpecialRun{ .lt_index = whitespace_end };
                        if (run.lt_index > text_start) {
                            try self.validateCharacterDataSpecials(self.input[text_start..run.lt_index], run.has_close_bracket, run.has_ampersand);
                            if (self.topIndex() == 0 and has_non_whitespace) return error.InvalidDocumentContent;
                            if (!drop_whitespace_text_nodes or has_non_whitespace) {
                                const parent_idx = self.topIndex();
                                _ = try self.appendTextNodeTo(parent_idx, text_start, run.lt_index);
                            }
                        }
                        self.i = run.lt_index;
                    } else {
                        const run = scanner.scanTextRun(self.input, self.i);
                        if (run.lt_index > self.i and (!drop_whitespace_text_nodes or run.has_non_whitespace)) {
                            const parent_idx = self.topIndex();
                            _ = try self.appendTextNodeTo(parent_idx, self.i, run.lt_index);
                        }
                        self.i = run.lt_index;
                    }
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
                    else => {
                        @branchHint(.likely);
                        try self.parseOpeningTag();
                    },
                }
            }

            if (require_closed_elements_on_eof and self.stackLen() > 1) {
                return error.UnexpectedEndOfData;
            }
            if (comptime strict_mode) {
                if (!self.root_seen) return error.ExpectedDocumentElement;
            }

            while (self.stackLen() > 1) {
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
            const name_scan = if (comptime validate_closing_tags)
                scanner.scanNameAndKeyAfterStart(self.input, self.i)
            else if (comptime strict_mode) blk: {
                const scan = scanner.scanNameEndAfterStart(self.input, self.i);
                break :blk scanner.NameScan{
                    .end = scan.end,
                    .key = 0,
                    .needs_unicode_validation = scan.needs_unicode_validation,
                };
            } else scanner.NameScan{ .end = scanner.findNameEnd(self.input, self.i), .key = 0 };
            const name_end = name_scan.end;
            if (comptime strict_mode) {
                if (name_scan.needs_unicode_validation and !document.isValidXmlName(self.input[name_start..name_end])) return error.ExpectedElementName;
            }
            self.i = name_end;

            const parent_idx = self.topIndex();
            if (comptime strict_mode) {
                if (parent_idx == 0) {
                    if (self.root_seen) return error.MultipleDocumentElements;
                    self.root_seen = true;
                }
            }
            const idx: IndexInt = if (comptime validate_closing_tags)
                InvalidIndex
            else
                try self.appendElementNodeTo(parent_idx, name_start, name_end);

            // Common path: start tag with no attributes.
            if (self.i < self.input.len) {
                const c0 = self.input[self.i];
                if (c0 == '>') {
                    self.i += 1;
                    const element_idx = if (comptime validate_closing_tags)
                        try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, 0, 0)
                    else
                        idx;
                    self.skipDroppedWhitespaceText();
                    if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                    try self.pushStack(element_idx, name_scan.key, name_end - name_start);
                    return;
                }

                if (c0 == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    self.i += 2;
                    if (comptime validate_closing_tags) {
                        _ = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, 0, 0);
                    }
                    return;
                }
            }

            const attr_start_idx: IndexInt = @intCast(self.doc.attrs.items.len);
            while (self.i < self.input.len) {
                const boundary = self.i;
                self.skipWhitespace();
                if (self.i >= self.input.len) return error.UnexpectedEndOfData;

                const c = self.input[self.i];
                if (c == '>') {
                    if (comptime strict_mode) {
                        const attr_end_idx = self.doc.attrs.items.len;
                        const attr_start_usize: usize = attr_start_idx;
                        if (attr_end_idx - attr_start_usize > 2) {
                            if (findDuplicateAttribute(self.input, self.doc.attrs.items[attr_start_usize..attr_end_idx])) |duplicate_start| {
                                self.i = duplicate_start;
                                return error.DuplicateAttribute;
                            }
                        }
                    }
                    self.i += 1;
                    const element_idx = if (comptime validate_closing_tags)
                        try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, attr_start_idx, @intCast(self.doc.attrs.items.len))
                    else blk: {
                        self.doc.nodes.items[idx].data.start = attr_start_idx;
                        self.doc.nodes.items[idx].data.end = @intCast(self.doc.attrs.items.len);
                        break :blk idx;
                    };
                    self.skipDroppedWhitespaceText();
                    if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                    try self.pushStack(element_idx, name_scan.key, name_end - name_start);
                    return;
                }

                if (c == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    if (comptime strict_mode) {
                        const attr_end_idx = self.doc.attrs.items.len;
                        const attr_start_usize: usize = attr_start_idx;
                        if (attr_end_idx - attr_start_usize > 2) {
                            if (findDuplicateAttribute(self.input, self.doc.attrs.items[attr_start_usize..attr_end_idx])) |duplicate_start| {
                                self.i = duplicate_start;
                                return error.DuplicateAttribute;
                            }
                        }
                    }
                    self.i += 2;
                    if (comptime validate_closing_tags) {
                        _ = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, attr_start_idx, @intCast(self.doc.attrs.items.len));
                    } else {
                        self.doc.nodes.items[idx].data.start = attr_start_idx;
                        self.doc.nodes.items[idx].data.end = @intCast(self.doc.attrs.items.len);
                    }
                    return;
                }

                if (strict_mode and self.i == boundary) {
                    @branchHint(.unlikely);
                    return error.ExpectedAttributeName;
                }
                if (!tables.isNameStart(c)) {
                    if (strict_mode) {
                        @branchHint(.unlikely);
                        return error.ExpectedAttributeName;
                    }
                    self.i += 1;
                    continue;
                }

                const attr_name_start = self.i;
                const attr_name_needs_unicode_validation = if (comptime strict_mode) blk: {
                    const scan = scanner.scanNameEndAfterStart(self.input, self.i);
                    self.i = scan.end;
                    break :blk scan.needs_unicode_validation;
                } else blk: {
                    self.i = scanner.findNameEnd(self.input, self.i);
                    break :blk false;
                };
                const attr_name_end = self.i;
                if (comptime strict_mode) {
                    if (attr_name_needs_unicode_validation and !document.isValidXmlName(self.input[attr_name_start..attr_name_end])) return error.ExpectedAttributeName;
                    const prior_count = self.doc.attrs.items.len - @as(usize, attr_start_idx);
                    if (prior_count == 1) {
                        const first_name = self.doc.attrs.items[@as(usize, attr_start_idx)].name.slice(self.input);
                        if (std.mem.eql(u8, first_name, self.input[attr_name_start..attr_name_end])) return error.DuplicateAttribute;
                    }
                }
                const input = self.input;
                const input_len = input.len;

                var value_start = self.i;
                var value_end = self.i;
                parse_value: {
                    if (self.i < input_len and input[self.i] != '=' and tables.isWhitespace(input[self.i])) self.skipWhitespace();
                    if (self.i + 1 < input_len and input[self.i] == '=') {
                        const quote = input[self.i + 1];
                        if (quote == '\'' or quote == '"') {
                            value_start = self.i + 2;
                            if (comptime strict_mode) {
                                const scan = scanner.scanQuotedValueSpecials(input, value_start, quote);
                                if (scan.end == input_len) return error.ExpectedQuote;
                                value_end = scan.end;
                                try self.validateAttributeValueSpecials(input[value_start..value_end], scan.has_lt, scan.has_ampersand);
                                self.i = scan.end + 1;
                            } else if (scanner.findByte(input, value_start, quote)) |quote_pos| {
                                value_end = quote_pos;
                                self.i = quote_pos + 1;
                            } else {
                                value_end = input_len;
                                self.i = input_len;
                            }
                            break :parse_value;
                        }
                    }

                    if (self.i < input_len and input[self.i] == '=') {
                        self.i += 1;
                        self.skipWhitespace();
                        if (self.i >= input_len) return error.UnexpectedEndOfData;

                        const value_first = input[self.i];
                        if (value_first == '\'' or value_first == '"') {
                            const quote = value_first;
                            self.i += 1;
                            value_start = self.i;
                            if (comptime strict_mode) {
                                const scan = scanner.scanQuotedValueSpecials(input, value_start, quote);
                                if (scan.end == input_len) return error.ExpectedQuote;
                                value_end = scan.end;
                                try self.validateAttributeValueSpecials(input[value_start..value_end], scan.has_lt, scan.has_ampersand);
                                self.i = scan.end + 1;
                            } else if (scanner.findByte(input, self.i, quote)) |quote_pos| {
                                value_end = quote_pos;
                                self.i = quote_pos + 1;
                            } else {
                                value_end = input_len;
                                self.i = input_len;
                            }
                        } else {
                            if (strict_mode) return error.ExpectedQuote;
                            value_start = self.i;
                            const raw_end = scanner.findAttrUnquotedEnd(input, self.i);
                            if (raw_end > value_start and raw_end < input_len and input[raw_end] == '>' and input[raw_end - 1] == '/') {
                                value_end = raw_end - 1;
                                self.i = raw_end - 1;
                            } else {
                                self.i = raw_end;
                                value_end = self.i;
                            }
                        }
                        break :parse_value;
                    }

                    if (strict_mode) {
                        @branchHint(.unlikely);
                        if (self.i >= input_len) return error.UnexpectedEndOfData;
                        return error.ExpectedEq;
                    }
                }

                const attr_len = self.doc.attrs.items.len;
                if (attr_len == self.doc.attrs.capacity) {
                    @branchHint(.unlikely);
                    self.doc.attrs.ensureTotalCapacityPrecise(self.doc.allocator, attr_len +| attr_len / 2 +| @as(usize, 8)) catch return error.OutOfMemory;
                }
                const attr_out = self.doc.attrs.addOneAssumeCapacity();
                attr_out.* = .{
                    .name = .{ .start = @intCast(attr_name_start), .end = @intCast(attr_name_end) },
                    .value = .{ .start = @intCast(value_start), .end = @intCast(value_end) },
                };
            }

            return error.UnexpectedEndOfData;
        }

        inline fn parseClosingTag(noalias self: *Self) ParseError!void {
            if (!validate_closing_tags) {
                self.i += 2; // </
                if (comptime strict_mode) {
                    if (self.i >= self.input.len) return error.UnexpectedEndOfData;
                    if (!tables.isNameStart(self.input[self.i])) return error.InvalidClosingTagName;
                    const close_name_start = self.i;
                    const close_scan = scanner.scanNameEndAfterStart(self.input, self.i);
                    self.i = close_scan.end;
                    if (close_scan.needs_unicode_validation and !document.isValidXmlName(self.input[close_name_start..self.i])) return error.InvalidClosingTagName;
                    if (self.i < self.input.len and tables.isWhitespace(self.input[self.i])) self.skipWhitespace();
                    if (self.i >= self.input.len) return error.UnexpectedEndOfData;
                    if (self.input[self.i] != '>') return error.InvalidClosingTagName;
                    self.i += 1;
                } else {
                    const gt = scanner.findByte(self.input, self.i, '>') orelse {
                        self.i = self.input.len;
                        return;
                    };
                    self.i = gt + 1;
                }
                if (self.stackLen() > 1) self.finishNode(self.popStack());
                return;
            }

            self.i += 2; // </

            if (self.i < self.input.len and tables.isWhitespace(self.input[self.i])) {
                if (strict_mode) return error.InvalidClosingTagName;
                self.skipWhitespace();
            }
            if (self.i >= self.input.len) {
                if (strict_mode) return error.UnexpectedEndOfData;
                return;
            }

            if (self.stackLen() <= 1) return error.InvalidClosingTagName;

            const top = self.doc.parse_validate_stack.items[self.doc.parse_validate_stack.items.len - 1];
            const close_start = self.i;
            const close_len: usize = top.tag_len;
            if (close_len > self.input.len - close_start) return error.InvalidClosingTagName;
            const close_end = close_start + close_len;
            const close_name = self.input[close_start..close_end];
            if (scanner.prefixKey(close_name) != top.tag_key) return error.InvalidClosingTagName;
            if (close_len > 8) {
                const open_name = self.doc.nodes.items[top.idx].name.slice(self.input);
                if (!std.mem.eql(u8, open_name[8..], close_name[8..])) return error.InvalidClosingTagName;
            }
            self.i = close_end;

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

            return error.InvalidClosingTagName;
        }

        fn parsePiOrDeclaration(noalias self: *Self) ParseError!void {
            const markup_start = self.i;
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
            const target_needs_unicode_validation = if (comptime strict_mode) blk: {
                const scan = scanner.scanNameEndAfterStart(self.input, self.i);
                self.i = scan.end;
                break :blk scan.needs_unicode_validation;
            } else blk: {
                self.i += 1;
                self.i = scanner.findNameEnd(self.input, self.i);
                break :blk false;
            };
            const target_end = self.i;
            if (comptime strict_mode) {
                if (target_needs_unicode_validation and !document.isValidXmlName(self.input[target_start..target_end])) return error.ExpectedPiTarget;
            }
            const xml_target = target_end - target_start == 3 and
                std.ascii.eqlIgnoreCase(self.input[target_start..target_end], "xml");
            if (comptime strict_mode) {
                if (xml_target and !std.mem.eql(u8, self.input[target_start..target_end], "xml")) return error.ExpectedPiTarget;
                if (xml_target and markup_start != 0) return error.InvalidDeclaration;
                if (xml_target and (target_end >= self.input.len or !tables.isWhitespace(self.input[target_end]))) return error.InvalidDeclaration;
                if (!xml_target) {
                    if (target_end >= self.input.len) return error.UnexpectedEndOfData;
                    if (!tables.isWhitespace(self.input[target_end])) {
                        if (self.input[target_end] != '?') return error.ExpectedGt;
                        if (target_end + 1 >= self.input.len) return error.UnexpectedEndOfData;
                        if (self.input[target_end + 1] != '>') return error.ExpectedGt;
                    }
                }
            }

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

            if (comptime strict_mode) {
                if (xml_target) {
                    const declaration = try document.validateXmlDeclaration(self.input[value_start..value_end]);
                    self.standalone_yes = declaration.standalone_yes;
                }
            }

            if (!opts.include_misc_nodes) return;

            const decl = xml_target;
            const kind: NodeType = if (decl) .declaration else .pi;

            const parent_idx = self.topIndex();
            _ = try self.appendNodeTo(parent_idx, .{
                .kind = kind,
                .name = .{ .start = @intCast(target_start), .end = @intCast(target_end) },
                .data = .{ .start = @intCast(value_start), .end = @intCast(value_end) },
            });
        }

        fn parseBangNode(noalias self: *Self) ParseError!void {
            if (self.i + 3 < self.input.len and self.input[self.i + 2] == '-' and self.input[self.i + 3] == '-') {
                const value_start = self.i + 4;
                const end = scanner.findSequence(self.input, value_start, "-->") orelse {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    self.i = self.input.len;
                    return;
                };
                if (comptime strict_mode) try validateComment(self.input[value_start..end]);
                self.i = end + 3;

                if (!opts.include_misc_nodes) return;

                const parent_idx = self.topIndex();
                _ = try self.appendNodeTo(parent_idx, .{
                    .kind = .comment,
                    .data = .{ .start = @intCast(value_start), .end = @intCast(end) },
                });
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

                if (comptime strict_mode) {
                    if (self.topIndex() == 0) return error.InvalidDocumentContent;
                }

                if (!opts.include_misc_nodes) return;

                const parent_idx = self.topIndex();
                _ = try self.appendNodeTo(parent_idx, .{
                    .kind = .cdata,
                    .data = .{ .start = @intCast(value_start), .end = @intCast(end) },
                });
                return;
            }

            if (scanner.isDoctype(self.input, self.i)) {
                if (comptime strict_mode) {
                    if (!scanner.isDoctypeExact(self.input, self.i)) return error.ExpectedGt;
                    if (self.topIndex() != 0 or self.root_seen or self.doctype_seen) return error.InvalidDoctype;
                }
                const j = scanner.findDoctypeEnd(self.input, self.i + 9) orelse {
                    if (strict_mode) return error.UnexpectedEndOfData;
                    self.i = self.input.len;
                    return;
                };

                const value_start = self.i + 9;
                const value_end = j;
                if (comptime strict_mode) {
                    const info = try document.validateDoctypeAlloc(self.doc.allocator, self.input[value_start..value_end]);
                    self.doctype_value_start = value_start;
                    self.doctype_value_end = value_end;
                    self.require_declared_entities = self.standalone_yes or (!info.has_external_id and !info.has_parameter_entity_references);
                    try document.validateDoctypeEntityConstraintsAlloc(
                        self.doc.allocator,
                        self.input[value_start..value_end],
                        self.require_declared_entities,
                    );
                }
                self.i = j + 1;

                if (comptime strict_mode) self.doctype_seen = true;

                if (expand_dtd_entities) {
                    try self.doc.registerDoctypeEntities(self.input[value_start..value_end]);
                }

                if (!opts.include_misc_nodes) return;

                const parent_idx = self.topIndex();
                _ = try self.appendNodeTo(parent_idx, .{
                    .kind = .doctype,
                    .data = .{ .start = @intCast(value_start), .end = @intCast(value_end) },
                });
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
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len +| len / 2 +| 8) catch return error.OutOfMemory;
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

        inline fn appendElementNodeWithAttrsTo(noalias self: *Self, parent_idx: IndexInt, name_start: usize, name_end: usize, attr_start: IndexInt, attr_end: IndexInt) ParseError!IndexInt {
            const len = self.doc.nodes.items.len;
            if (len == self.doc.nodes.capacity) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len +| len / 2 +| 8) catch return error.OutOfMemory;
            }
            var parent = &self.doc.nodes.items[parent_idx];
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = .{
                .kind = .element,
                .name = .{ .start = @intCast(name_start), .end = @intCast(name_end) },
                .data = .{ .start = attr_start, .end = attr_end },
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
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len +| len / 2 +| 8) catch return error.OutOfMemory;
            }
            var parent = &self.doc.nodes.items[parent_idx];
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = .{
                .kind = .text,
                .data = .{ .start = @intCast(start), .end = @intCast(end) },
                .parent = parent_idx,
                .prev_sibling = parent.last_child,
                .subtree_end = idx,
            };
            parent.last_child = idx;
            return idx;
        }

        inline fn appendNodeTo(noalias self: *Self, parent_idx: IndexInt, node: document.RawNode) ParseError!IndexInt {
            const len = self.doc.nodes.items.len;
            if (len == self.doc.nodes.capacity) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len +| len / 2 +| 8) catch return error.OutOfMemory;
            }

            var parent = &self.doc.nodes.items[parent_idx];
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = node;
            out.parent = parent_idx;
            out.prev_sibling = parent.last_child;
            out.subtree_end = idx;
            parent.last_child = idx;
            return idx;
        }

        inline fn pushStack(noalias self: *Self, idx: IndexInt, tag_key: u64, tag_len: usize) ParseError!void {
            if (comptime validate_closing_tags) {
                const len = self.doc.parse_validate_stack.items.len;
                if (len == self.doc.parse_validate_stack.capacity) {
                    @branchHint(.unlikely);
                    self.doc.parse_validate_stack.ensureTotalCapacityPrecise(self.doc.allocator, len +| len / 2 +| @as(usize, 8)) catch return error.OutOfMemory;
                }
                self.doc.parse_validate_stack.appendAssumeCapacity(.{ .idx = idx, .tag_key = tag_key, .tag_len = @intCast(tag_len) });
            } else {
                self.current_parent = idx;
            }
        }

        inline fn popStack(noalias self: *Self) IndexInt {
            if (comptime validate_closing_tags) {
                return self.doc.parse_validate_stack.pop().?.idx;
            } else {
                const idx = self.current_parent;
                self.current_parent = self.doc.nodes.items[idx].parent;
                return idx;
            }
        }

        inline fn stackLen(self: *const Self) usize {
            if (comptime validate_closing_tags) return self.doc.parse_validate_stack.items.len;
            return if (self.current_parent == 0) 1 else 2;
        }

        inline fn topIndex(self: *const Self) IndexInt {
            if (comptime validate_closing_tags) {
                return self.doc.parse_validate_stack.items[self.doc.parse_validate_stack.items.len - 1].idx;
            }
            return self.current_parent;
        }

        inline fn finishNode(noalias self: *Self, idx: IndexInt) void {
            self.doc.nodes.items[idx].subtree_end = @intCast(self.doc.nodes.items.len - 1);
        }

        inline fn skipWhitespace(noalias self: *Self) void {
            if (self.i >= self.input.len) return;
            const c = self.input[self.i];
            if (c == ' ') {
                const next = self.i + 1;
                if (comptime strict_mode) {
                    // All XML whitespace bytes are <= ASCII space. Keep the
                    // ordinary ` space + token` path to one extra comparison,
                    // but fall through for mixed space/newline/tab/CR runs.
                    if (next >= self.input.len or self.input[next] > ' ') {
                        self.i = next;
                        return;
                    }
                } else if (next >= self.input.len or !tables.isWhitespace(self.input[next])) {
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
            name_end: usize,
            name_key: u64,
        ) ParseError!bool {
            // Fast-path the common `<tag>text</tag>` shape to avoid pushing a
            // stack frame only to immediately pop it again on the closing tag.
            const text_start = self.i;
            if (text_start >= self.input.len or self.input[text_start] == '<') return false;

            var has_close_bracket = false;
            var has_ampersand = false;
            const lt = if (comptime strict_mode) blk: {
                const specials = scanner.scanTextSpecials(self.input, text_start);
                has_close_bracket = specials.has_close_bracket;
                has_ampersand = specials.has_ampersand;
                break :blk specials.lt_index;
            } else scanner.findByte(self.input, text_start, '<') orelse return false;
            if (lt >= self.input.len or lt == text_start or lt + 2 >= self.input.len or self.input[lt + 1] != '/') return false;

            const close_start = lt + 2;
            const close_end = close_start + (name_end - name_start);
            if (close_end > self.input.len) return false;
            const open_key = if (comptime validate_closing_tags) name_key else scanner.prefixKey(self.input[name_start..name_end]);
            if (scanner.prefixKey(self.input[close_start..close_end]) != open_key) return false;
            if (name_end - name_start > 8 and !std.mem.eql(u8, self.input[name_start + 8 .. name_end], self.input[close_start + 8 .. close_end])) return false;

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
            if (comptime strict_mode) try self.validateCharacterDataSpecials(raw, has_close_bracket, has_ampersand);
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

        inline fn validateAttributeValueSpecials(self: *const Self, value: []const u8, has_lt: bool, has_ampersand: bool) ParseError!void {
            if (has_lt) return error.InvalidAttributeValue;
            if (has_ampersand) {
                try document.validateXmlAttributeReferencesAlloc(self.doc.allocator, value, self.doctypeValue(), self.require_declared_entities);
            }
        }

        inline fn validateComment(value: []const u8) ParseError!void {
            if (std.mem.indexOf(u8, value, "--") != null or (value.len != 0 and value[value.len - 1] == '-')) return error.InvalidComment;
        }

        inline fn validateCharacterData(self: *const Self, value: []const u8) ParseError!void {
            const specials = scanner.bytePairPresence(value, ']', '&');
            return self.validateCharacterDataSpecials(value, specials.first, specials.second);
        }

        inline fn validateCharacterDataSpecials(self: *const Self, value: []const u8, has_close_bracket: bool, has_ampersand: bool) ParseError!void {
            if (has_close_bracket and std.mem.indexOf(u8, value, "]]>") != null) return error.InvalidCharacterData;
            if (has_ampersand) {
                try document.validateXmlReferencesAlloc(self.doc.allocator, value, false, self.doctypeValue(), self.require_declared_entities);
            }
        }

        inline fn doctypeValue(self: *const Self) ?[]const u8 {
            if (!self.doctype_seen) return null;
            return self.input[self.doctype_value_start..self.doctype_value_end];
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

test "strict start-tag grammar rejects malformed attributes" {
    const options: ParseOptions = .{};
    const Document = document.Types(options).Document;
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    const Case = struct { input: []const u8, err: ParseError };
    const cases = [_]Case{
        .{ .input = "<r a/>", .err = error.ExpectedEq },
        .{ .input = "<r !a='1'/>", .err = error.ExpectedAttributeName },
        .{ .input = "<r a='1'b='2'/>", .err = error.ExpectedAttributeName },
        .{ .input = "<r a='1' b/>", .err = error.ExpectedEq },
        .{ .input = "<r a='x<y'/>", .err = error.InvalidAttributeValue },
        .{ .input = "<r><!--a--b--></r>", .err = error.InvalidComment },
        .{ .input = "<r><!--a---></r>", .err = error.InvalidComment },
        .{ .input = "<r>x]]>y</r>", .err = error.InvalidCharacterData },
    };

    for (cases) |case| {
        doc.clear();
        doc.source = case.input;
        try std.testing.expectError(case.err, parseInto(&doc, case.input, .{ .mode = .strict, .validate_closing_tags = true }));
    }

    doc.clear();
    doc.source = "<r></ r>";
    try std.testing.expectError(error.InvalidClosingTagName, parseInto(&doc, doc.source, .{ .mode = .strict, .validate_closing_tags = true }));

    inline for (.{ "<r></ r>", "<r></>", "<r></r x>", "<r></r" }) |input| {
        doc.clear();
        doc.source = input;
        const result = parseInto(&doc, input, .{ .mode = .strict, .validate_closing_tags = false });
        if (std.mem.eql(u8, input, "<r></r")) {
            try std.testing.expectError(error.UnexpectedEndOfData, result);
        } else {
            try std.testing.expectError(error.InvalidClosingTagName, result);
        }
    }
}

test "strict closing validation supports tag names longer than u16" {
    const options: ParseOptions = .{};
    const Document = document.Types(options).Document;
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

    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    doc.source = source;
    try parseInto(&doc, source, .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true });
    try std.testing.expectEqual(@as(usize, name_len), doc.nodeAt(1).?.nameSlice().len);
}

test "turbo mode accepts mixed XML whitespace around attribute equals" {
    const options: ParseOptions = .{};
    const Document = document.Types(options).Document;
    const source = "<r a \n \t=\r '1' b \r\n = \t\"2\"></r \n>";
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    doc.source = source;
    try parseInto(&doc, source, .{ .mode = .turbo, .validate_closing_tags = true, .require_closed_elements_on_eof = true });
    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("1", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("2", root.getAttributeValueRaw("b").?);
}

test "strict start tags accept mixed XML whitespace between attributes" {
    const options: ParseOptions = .{};
    const Document = document.Types(options).Document;
    const source = "<r \n\t a='1' \r\n b=\"2\">x</r>";
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    doc.source = source;
    try parseInto(&doc, source, .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true });
    try std.testing.expectEqual(@as(usize, 2), doc.attrs.items.len);
}
