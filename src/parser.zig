const std = @import("std");
const builtin = @import("builtin");
const common = @import("common.zig");
const document = @import("document.zig");
const scanner = @import("scanner.zig");
const tables = @import("tables.zig");

const ParseOptions = document.ParseOptions;
const ParseError = document.ParseError;
const NodeType = document.NodeType;
const IndexInt = document.IndexInt;
const InvalidIndex = document.InvalidIndex;

const duplicate_helper_section = switch (builtin.os.tag) {
    .macos, .ios, .tvos, .watchos, .visionos => "__TEXT,__text",
    else => ".text.unlikely.zxml",
};

inline fn attributeNameHash(name: []const u8) u64 {
    var mixed = scanner.prefixKey(name) ^ (@as(u64, name.len) << 56);
    mixed *%= 0x9e3779b97f4a7c15;
    mixed ^= mixed >> 32;
    return mixed;
}

inline fn attributeNameHashLarge(name: []const u8) u64 {
    const key: u64 = if (name.len <= 4) blk: {
        const bytes: *align(1) const [4]u8 = @ptrCast(name.ptr);
        const word = std.mem.readInt(u32, bytes, .little);
        const shift: u5 = @intCast((4 - name.len) * 8);
        break :blk word & (@as(u32, 0xffffffff) >> shift);
    } else blk: {
        const bytes: *align(1) const [8]u8 = @ptrCast(name.ptr);
        const word = std.mem.readInt(u64, bytes, .little);
        if (name.len >= 8) break :blk word;
        const shift: u6 = @intCast((8 - name.len) * 8);
        break :blk word & (@as(u64, 0xffffffffffffffff) >> shift);
    };
    var mixed = key ^ (@as(u64, name.len) << 56);
    mixed *%= 0x9e3779b97f4a7c15;
    mixed ^= mixed >> 32;
    return mixed;
}

noinline fn findDuplicateAttributeQuadratic(input: []const u8, attrs: []const document.RawAttribute) align(256) linksection(".text.unlikely.zxml") ?usize {
    @branchHint(.cold);
    if (attrs.len >= 32 and attrs.len <= 262144) {
        @branchHint(.unlikely);
        if (attrs.len <= 96) return findDuplicateAttributeLarge(128, input, attrs);
        return findDuplicateAttributeLarge(4096, input, attrs);
    }
    for (attrs, 0..) |current, i| {
        const current_name = current.name.slice(input);
        for (attrs[0..i]) |previous| {
            if (std.mem.eql(u8, previous.name.slice(input), current_name)) return current.name.start;
        }
    }
    return null;
}

noinline fn findDuplicateAttributeLarge(comptime table_capacity: usize, input: []const u8, attrs: []const document.RawAttribute) linksection(".text.unlikely.zxml") ?usize {
    @branchHint(.cold);
    if (comptime table_capacity == 128) {
        var slots = [_]u32{0} ** table_capacity;
        for (attrs, 0..) |attr, attr_index| {
            const name = attr.name.slice(input);
            const hash = attributeNameHashLarge(name);
            const fingerprint: u32 = @as(u32, @truncate(hash)) | 1;
            var slot_index: usize = @intCast(hash >> 57);
            while (true) {
                if (slots[slot_index] == 0) {
                    slots[slot_index] = fingerprint;
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

    var slots: [table_capacity]u32 = undefined;
    var occupied = [_]u64{0} ** (table_capacity / 64);
    const slot_shift: u6 = comptime @intCast(@as(u7, 64) - @as(u7, std.math.log2_int(usize, table_capacity)));

    if (comptime table_capacity == 4096) {
        if (attrs.len > table_capacity) {
            const max_partition_bits: u6 = 12;
            const max_partition_count = @as(usize, 1) << max_partition_bits;
            const partition_counts = slots[0..max_partition_count];
            @memset(partition_counts, 0);
            for (attrs) |attr| {
                const hash = std.hash.Wyhash.hash(0, attr.name.slice(input));
                const partition_index: usize = @intCast(
                    (hash >> @intCast(64 - 12 - max_partition_bits)) & (max_partition_count - 1),
                );
                partition_counts[partition_index] += 1;
            }

            var partition_bits: u6 = 1;
            partition_select: while (partition_bits <= max_partition_bits) : (partition_bits += 1) {
                const partition_count = @as(usize, 1) << partition_bits;
                const max_parts_per_partition = max_partition_count / partition_count;
                for (0..partition_count) |partition| {
                    var count: u32 = 0;
                    const first = partition * max_parts_per_partition;
                    for (partition_counts[first .. first + max_parts_per_partition]) |part_count| count += part_count;
                    if (count > table_capacity) continue :partition_select;
                }
                break;
            }

            if (partition_bits <= max_partition_bits) {
                const partition_count = @as(usize, 1) << partition_bits;
                const partition_mask = partition_count - 1;
                for (0..partition_count) |partition| {
                    @memset(&occupied, 0);
                    for (attrs, 0..) |attr, attr_index| {
                        const name = attr.name.slice(input);
                        const hash = std.hash.Wyhash.hash(0, name);
                        const partition_index: usize = @intCast(
                            (hash >> @intCast(64 - 12 - partition_bits)) & partition_mask,
                        );
                        if (partition_index != partition) continue;

                        const fingerprint: u32 = @truncate(hash);
                        var slot_index: usize = @intCast(hash >> slot_shift);
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
                }
                return null;
            }

            for (attrs, 0..) |current, i| {
                const current_name = current.name.slice(input);
                for (attrs[0..i]) |previous| {
                    if (std.mem.eql(u8, previous.name.slice(input), current_name)) return current.name.start;
                }
            }
            return null;
        }
    }

    for (attrs, 0..) |attr, attr_index| {
        const name = attr.name.slice(input);
        const hash = attributeNameHashLarge(name);
        const fingerprint: u32 = @truncate(hash);
        var slot_index: usize = @intCast(hash >> slot_shift);
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

noinline fn equalLongAttributePairNames(input: []const u8, first: document.Span, second: document.Span) linksection(duplicate_helper_section) bool {
    std.debug.assert(first.len() == second.len() and first.len() > 1);
    return std.mem.eql(u8, first.slice(input), second.slice(input));
}

inline fn findDuplicateAttributePair(input: []const u8, attrs: []const document.RawAttribute) ?usize {
    std.debug.assert(attrs.len == 2);
    const first = attrs[0].name;
    const second = attrs[1].name;
    const first_len = first.len();
    if (first_len != second.len()) return null;
    if (first_len == 1) return if (input[first.start] == input[second.start]) second.start else null;
    return if (equalLongAttributePairNames(input, first, second)) second.start else null;
}

noinline fn findDuplicateAttribute(input: []const u8, attrs: []const document.RawAttribute) align(128) linksection(duplicate_helper_section) ?usize {
    if (attrs.len >= 32 and attrs.len <= 4096) {
        @branchHint(.unlikely);
        if (attrs.len <= 96) return findDuplicateAttributeLarge(128, input, attrs);
        return findDuplicateAttributeLarge(4096, input, attrs);
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
    return parseIntoTracked(doc, input, opts, false);
}

pub fn parseIntoTracked(noalias doc: anytype, input: []const u8, comptime opts: ParseOptions, comptime track_error_offset: bool) ParseError!void {
    if (comptime track_error_offset) doc.last_error_offset = 0;
    if (!common.lenFits(input.len)) return error.InputTooLarge;
    if (comptime opts.mode == .strict and opts.validate_well_formedness and opts.validate_xml_characters) try document.validateXmlCharacters(input);
    var p = Parser(opts, @TypeOf(doc.*)){ .doc = doc, .input = input, .i = 0 };
    p.parse() catch |err| {
        if (comptime opts.validate_closing_tags) doc.parse_validate_stack.items.len = 0;
        if (comptime track_error_offset) doc.last_error_offset = @min(p.i, input.len);
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

        const strict_mode = opts.mode == .strict and opts.validate_well_formedness;
        const full_navigation_index = opts.navigation_index == .full;
        const validate_closing_tags = opts.validate_closing_tags;
        const require_closed_elements_on_eof = opts.require_closed_elements_on_eof;
        const expand_dtd_entities = opts.expand_dtd_entities;
        const drop_whitespace_text_nodes = opts.drop_whitespace_text_nodes;

        inline fn scanOpeningName(input: []const u8, start: usize) scanner.NameScan {
            std.debug.assert(start < input.len and tables.NameCharTable[input[start]]);
            var i = start + 1;
            var key: u64 = input[start];
            var high_bits: u8 = input[start];
            inline for (1..4) |n| {
                if (i >= input.len or !tables.NameCharTable[input[i]]) return .{
                    .end = i,
                    .key = key,
                    .needs_unicode_validation = (high_bits & 0x80) != 0,
                };
                const c = input[i];
                high_bits |= c;
                key |= @as(u64, c) << @intCast(n * 8);
                i += 1;
            }
            if (i + 4 > input.len) return scanOpeningNameNearEnd(input, start, i, key, high_bits);
            inline for (4..8) |n| {
                if (!tables.NameCharTable[input[i]]) return .{
                    .end = i,
                    .key = key,
                    .needs_unicode_validation = (high_bits & 0x80) != 0,
                };
                const c = input[i];
                high_bits |= c;
                key |= @as(u64, c) << @intCast(n * 8);
                i += 1;
            }
            const tail = scanner.scanNameEnd(input, i);
            return .{
                .end = tail.end,
                .key = key,
                .needs_unicode_validation = (high_bits & 0x80) != 0 or tail.needs_unicode_validation,
            };
        }

        noinline fn scanOpeningNameNearEnd(input: []const u8, start: usize, initial_i: usize, initial_key: u64, initial_high_bits: u8) scanner.NameScan {
            @branchHint(.cold);
            var i = initial_i;
            var key = initial_key;
            var high_bits = initial_high_bits;
            while (i < input.len) : (i += 1) {
                const c = input[i];
                if (!tables.NameCharTable[c]) break;
                high_bits |= c;
                key |= @as(u64, c) << @intCast((i - start) * 8);
            }
            return .{ .end = i, .key = key, .needs_unicode_validation = (high_bits & 0x80) != 0 };
        }

        fn parse(noalias self: *Self) align(128) ParseError!void {
            try self.doc.reserveForInput(self.input.len, opts);
            if (comptime validate_closing_tags) {
                std.debug.assert(self.doc.parse_validate_stack.items.len == 0);
            }
            std.debug.assert(self.doc.nodes.items.len == 0);
            _ = self.doc.nodes.addOneAssumeCapacity();
            self.doc.nodes.items[0] = .{
                .kind = .document,
                .parent = InvalidIndex,
            };
            if (comptime full_navigation_index) {
                self.doc.navigation.appendAssumeCapacity(.{ .subtree_end = 0 });
            }
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
                        if (comptime drop_whitespace_text_nodes) {
                            if (tables.WhitespaceTable[self.input[self.i]]) {
                                const whitespace_end = scanner.skipWhitespace(self.input, self.i);
                                if (whitespace_end >= self.input.len or self.input[whitespace_end] == '<') {
                                    self.i = whitespace_end;
                                    continue;
                                }
                            }
                        }
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
                scanOpeningName(self.input, self.i)
            else if (comptime strict_mode) blk: {
                const scan = scanner.scanNameEndAfterStart(self.input, self.i);
                break :blk scanner.NameScan{
                    .end = scan.end,
                    .key = 0,
                    .needs_unicode_validation = scan.needs_unicode_validation,
                };
            } else scanner.NameScan{ .end = scanner.findNameEndAfterStart(self.input, self.i), .key = 0 };
            const name_end = name_scan.end;
            if (name_end - name_start > std.math.maxInt(u16)) {
                @branchHint(.unlikely);
                return error.InputTooLarge;
            }
            if (comptime strict_mode) {
                if (name_scan.needs_unicode_validation and !document.isValidXmlNameAssumeValidUtf8(self.input[name_start..name_end])) return error.ExpectedElementName;
            }
            self.i = name_end;

            const parent_idx = self.topIndex();
            if (comptime strict_mode) {
                if (parent_idx == 0) {
                    if (self.root_seen) return error.MultipleDocumentElements;
                    self.root_seen = true;
                }
            }
            // Common path: start tag with no attributes.
            if (self.i >= self.input.len) return error.UnexpectedEndOfData;
            const c0 = self.input[self.i];
            if (comptime strict_mode) {
                if (c0 == '>') {
                    self.i += 1;
                    self.skipDroppedWhitespaceText();
                    if (comptime !validate_closing_tags and !strict_mode) {
                        if (try self.tryAppendSimpleTextElement(parent_idx, name_start, name_end, @intCast(name_end), @intCast(name_end))) return;
                    }
                    const element_idx = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, @intCast(name_end), @intCast(name_end));
                    if (comptime validate_closing_tags or strict_mode) {
                        if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                    }
                    try self.pushStack(element_idx, name_scan.key, name_end - name_start);
                    return;
                }
            } else {
                if (c0 == '>') {
                    @branchHint(.likely);
                    self.i += 1;
                    self.skipDroppedWhitespaceText();
                    if (comptime !strict_mode) {
                        if (try self.tryAppendSimpleTextElement(parent_idx, name_start, name_end, @intCast(name_end), @intCast(name_end))) return;
                    }
                    const element_idx = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, @intCast(name_end), @intCast(name_end));
                    if (comptime validate_closing_tags or strict_mode) {
                        if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                    }
                    try self.pushStack(element_idx, name_scan.key, name_end - name_start);
                    return;
                }
            }

            if (comptime strict_mode) {
                if (c0 == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    self.i += 2;
                    _ = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, @intCast(name_end), @intCast(name_end));
                    return;
                }
            } else if (self.i + 1 < self.input.len) {
                const terminator_pair = std.mem.readInt(u16, self.input[self.i..][0..2], .little);
                if (terminator_pair == (@as(u16, '>') << 8 | @as(u16, '/'))) {
                    self.i += 2;
                    _ = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, @intCast(name_end), @intCast(name_end));
                    return;
                }
            }

            const attr_start = self.i;
            if (comptime !strict_mode) {
                const tail = if (comptime opts.quote_aware_attribute_boundaries)
                    scanner.scanStartTagEnd(self.input, attr_start) orelse {
                        self.i = self.input.len;
                        return error.UnexpectedEndOfData;
                    }
                else blk: {
                    const end = scanner.findByte(self.input, attr_start, '>') orelse {
                        self.i = self.input.len;
                        return error.UnexpectedEndOfData;
                    };
                    break :blk scanner.StartTagEndScan{
                        .end = end,
                        .self_closing = end > attr_start and self.input[end - 1] == '/',
                    };
                };

                const attr_end: usize = if (tail.self_closing) tail.end - 1 else tail.end;
                self.i = tail.end + 1;
                if (tail.self_closing) {
                    _ = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, @intCast(attr_start), @intCast(attr_end));
                    return;
                }

                const attr_start_idx: IndexInt = @intCast(attr_start);
                const attr_end_idx: IndexInt = @intCast(attr_end);
                self.skipDroppedWhitespaceText();
                if (comptime !strict_mode) {
                    if (try self.tryAppendSimpleTextElement(parent_idx, name_start, name_end, attr_start_idx, attr_end_idx)) return;
                }
                const element_idx = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, attr_start_idx, attr_end_idx);
                if (comptime validate_closing_tags) {
                    if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                }
                try self.pushStack(element_idx, name_scan.key, name_end - name_start);
                return;
            }
            self.doc.parse_attrs.items.len = 0;
            while (self.i < self.input.len) {
                const boundary = self.i;
                self.skipWhitespace();
                if (self.i >= self.input.len) return error.UnexpectedEndOfData;

                const c = self.input[self.i];
                if (c == '>') {
                    const attr_end = self.i;
                    if (comptime strict_mode) {
                        const input = self.input;
                        try self.validateDeferredDtdAttributeReferences(input, attr_start, attr_end);
                        const attrs = self.doc.parse_attrs.items;
                        const duplicate_start = if (attrs.len == 2)
                            findDuplicateAttributePair(input, attrs)
                        else if (attrs.len > 2)
                            findDuplicateAttribute(input, attrs)
                        else
                            null;
                        if (duplicate_start) |duplicate| {
                            self.i = duplicate;
                            return error.DuplicateAttribute;
                        }
                    }
                    self.i += 1;
                    const attr_start_idx: IndexInt = @intCast(attr_start);
                    const attr_end_idx: IndexInt = @intCast(attr_end);
                    self.skipDroppedWhitespaceText();
                    if (comptime !validate_closing_tags and !strict_mode) {
                        if (try self.tryAppendSimpleTextElement(parent_idx, name_start, name_end, attr_start_idx, attr_end_idx)) return;
                    }
                    const element_idx = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, attr_start_idx, attr_end_idx);
                    if (comptime validate_closing_tags or strict_mode) {
                        if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                    }
                    try self.pushStack(element_idx, name_scan.key, name_end - name_start);
                    return;
                }

                if (c == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    const attr_end = self.i;
                    if (comptime strict_mode) {
                        const input = self.input;
                        try self.validateDeferredDtdAttributeReferences(input, attr_start, attr_end);
                        const attrs = self.doc.parse_attrs.items;
                        const duplicate_start = if (attrs.len == 2)
                            findDuplicateAttributePair(input, attrs)
                        else if (attrs.len > 2)
                            findDuplicateAttribute(input, attrs)
                        else
                            null;
                        if (duplicate_start) |duplicate| {
                            self.i = duplicate;
                            return error.DuplicateAttribute;
                        }
                    }
                    self.i += 2;
                    _ = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, @intCast(attr_start), @intCast(attr_end));
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
                    if (attr_name_needs_unicode_validation and !document.isValidXmlNameAssumeValidUtf8(self.input[attr_name_start..attr_name_end])) return error.ExpectedAttributeName;
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

                if (comptime strict_mode) {
                    const attr_len = self.doc.parse_attrs.items.len;
                    if (attr_len == self.doc.parse_attrs.capacity) {
                        @branchHint(.unlikely);
                        self.doc.parse_attrs.ensureTotalCapacityPrecise(
                            self.doc.allocator,
                            attr_len +| attr_len / 2 +| @as(usize, 8),
                        ) catch return error.OutOfMemory;
                    }
                    self.doc.parse_attrs.addOneAssumeCapacity().* = .{
                        .name = .{ .start = @intCast(attr_name_start), .end = @intCast(attr_name_end) },
                        .value = .{ .start = @intCast(value_start), .end = @intCast(value_end) },
                    };
                }
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
                    if (close_scan.needs_unicode_validation and !document.isValidXmlNameAssumeValidUtf8(self.input[close_name_start..self.i])) return error.InvalidClosingTagName;
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
                const open_name = self.doc.nodes.items[top.idx].nameSpan().slice(self.input);
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
                if (target_needs_unicode_validation and !document.isValidXmlNameAssumeValidUtf8(self.input[target_start..target_end])) return error.ExpectedPiTarget;
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
                .data = .{ .start = @intCast(value_start), .end = @intCast(value_end) },
                .name_len = @truncate(target_end - target_start),
                .name_gap = @truncate(value_start - target_end),
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
                        null,
                    );
                    self.standalone_yes = false;
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
                if (comptime full_navigation_index) self.doc.navigation.ensureTotalCapacityPrecise(self.doc.allocator, self.doc.nodes.capacity) catch return error.OutOfMemory;
            }
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = .{
                .kind = .element,
                .data = .{ .start = @intCast(name_end), .end = @intCast(name_end) },
                .name_len = @truncate(name_end - name_start),
                .parent = parent_idx,
            };
            if (comptime full_navigation_index) {
                const prev = self.doc.navigation.items[parent_idx].last_child;
                self.doc.navigation.appendAssumeCapacity(.{ .subtree_end = idx, .prev_sibling = prev });
                self.doc.navigation.items[parent_idx].last_child = idx;
            }
            return idx;
        }

        inline fn appendElementNodeWithAttrsTo(noalias self: *Self, parent_idx: IndexInt, name_start: usize, name_end: usize, attr_start: IndexInt, attr_end: IndexInt) ParseError!IndexInt {
            const len = self.doc.nodes.items.len;
            if (len == self.doc.nodes.capacity) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len +| len / 2 +| 8) catch return error.OutOfMemory;
                if (comptime full_navigation_index) self.doc.navigation.ensureTotalCapacityPrecise(self.doc.allocator, self.doc.nodes.capacity) catch return error.OutOfMemory;
            }
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = .{
                .kind = .element,
                .data = .{ .start = attr_start, .end = attr_end },
                .name_len = @truncate(name_end - name_start),
                .parent = parent_idx,
            };
            if (comptime full_navigation_index) {
                const prev = self.doc.navigation.items[parent_idx].last_child;
                self.doc.navigation.appendAssumeCapacity(.{ .subtree_end = idx, .prev_sibling = prev });
                self.doc.navigation.items[parent_idx].last_child = idx;
            }
            return idx;
        }

        inline fn appendTextNodeTo(noalias self: *Self, parent_idx: IndexInt, start_: usize, end_: usize) ParseError!IndexInt {
            const len = self.doc.nodes.items.len;
            if (len == self.doc.nodes.capacity) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len +| len / 2 +| 8) catch return error.OutOfMemory;
                if (comptime full_navigation_index) self.doc.navigation.ensureTotalCapacityPrecise(self.doc.allocator, self.doc.nodes.capacity) catch return error.OutOfMemory;
            }
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = .{
                .kind = .text,
                .data = .{ .start = @intCast(start_), .end = @intCast(end_) },
                .parent = parent_idx,
            };
            if (comptime full_navigation_index) {
                const prev = self.doc.navigation.items[parent_idx].last_child;
                self.doc.navigation.appendAssumeCapacity(.{ .subtree_end = idx, .prev_sibling = prev });
                self.doc.navigation.items[parent_idx].last_child = idx;
            }
            return idx;
        }

        inline fn appendNodeTo(noalias self: *Self, parent_idx: IndexInt, node: document.RawNode) ParseError!IndexInt {
            const len = self.doc.nodes.items.len;
            if (len == self.doc.nodes.capacity) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len +| len / 2 +| 8) catch return error.OutOfMemory;
                if (comptime full_navigation_index) self.doc.navigation.ensureTotalCapacityPrecise(self.doc.allocator, self.doc.nodes.capacity) catch return error.OutOfMemory;
            }
            const idx: IndexInt = @intCast(len);
            const out = self.doc.nodes.addOneAssumeCapacity();
            out.* = node;
            out.parent = parent_idx;
            if (comptime full_navigation_index) {
                const prev = self.doc.navigation.items[parent_idx].last_child;
                self.doc.navigation.appendAssumeCapacity(.{ .subtree_end = idx, .prev_sibling = prev });
                self.doc.navigation.items[parent_idx].last_child = idx;
            }
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
            if (comptime validate_closing_tags) return self.doc.parse_validate_stack.items.len + 1;
            return if (self.current_parent == 0) 1 else 2;
        }

        inline fn topIndex(self: *const Self) IndexInt {
            if (comptime validate_closing_tags) {
                if (self.doc.parse_validate_stack.items.len == 0) return 0;
                return self.doc.parse_validate_stack.items[self.doc.parse_validate_stack.items.len - 1].idx;
            }
            return self.current_parent;
        }

        inline fn finishNode(noalias self: *Self, idx: IndexInt) void {
            if (comptime full_navigation_index) self.doc.navigation.items[idx].subtree_end = @intCast(self.doc.nodes.items.len - 1);
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

        inline fn tryAppendSimpleTextElement(
            noalias self: *Self,
            parent_idx: IndexInt,
            name_start: usize,
            name_end: usize,
            attr_start: IndexInt,
            attr_end: IndexInt,
        ) ParseError!bool {
            comptime std.debug.assert(!strict_mode);
            const text_start = self.i;
            if (text_start >= self.input.len or self.input[text_start] == '<') return false;

            const lt = scanner.findTextEnd(self.input, text_start) orelse return false;
            if (lt == text_start or lt + 2 >= self.input.len or self.input[lt + 1] != '/') return false;

            const close_start = lt + 2;
            const j = if (comptime validate_closing_tags) blk: {
                const name_len = name_end - name_start;
                const close_end = close_start + name_len;
                if (close_end > self.input.len) return false;
                const open_key = scanner.prefixKey(self.input[name_start..name_end]);
                if (scanner.prefixKey(self.input[close_start..close_end]) != open_key) return false;
                if (name_len > 8 and !std.mem.eql(u8, self.input[name_start + 8 .. name_end], self.input[close_start + 8 .. close_end])) return false;

                var end = close_end;
                if (end >= self.input.len) return false;
                if (self.input[end] == '>') {
                    end += 1;
                } else if (tables.isWhitespace(self.input[end])) {
                    end = scanner.skipWhitespace(self.input, end);
                    if (end >= self.input.len or self.input[end] != '>') return false;
                    end += 1;
                } else {
                    return false;
                }
                break :blk end;
            } else blk: {
                const gt = scanner.findByte(self.input, close_start, '>') orelse return false;
                break :blk gt + 1;
            };

            self.i = j;
            const raw = self.input[text_start..lt];
            if (drop_whitespace_text_nodes and tables.isWhitespace(raw[0]) and scanner.skipWhitespace(raw, 0) == raw.len) {
                _ = try self.appendElementNodeWithAttrsTo(parent_idx, name_start, name_end, attr_start, attr_end);
                return true;
            }

            const len = self.doc.nodes.items.len;
            if (self.doc.nodes.capacity - len < 2) {
                @branchHint(.unlikely);
                self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len +| len / 2 +| 8) catch return error.OutOfMemory;
                if (self.doc.nodes.capacity - len < 2) self.doc.nodes.ensureTotalCapacityPrecise(self.doc.allocator, len + 2) catch return error.OutOfMemory;
            }
            const element_idx: IndexInt = @intCast(len);
            const text_idx: IndexInt = @intCast(len + 1);
            const out = self.doc.nodes.addManyAsArrayAssumeCapacity(2);
            out[0] = .{
                .kind = .element,
                .data = .{ .start = attr_start, .end = attr_end },
                .name_len = @truncate(name_end - name_start),
                .parent = parent_idx,
            };
            out[1] = .{
                .kind = .text,
                .data = .{ .start = @intCast(text_start), .end = @intCast(lt) },
                .parent = element_idx,
            };
            if (comptime full_navigation_index) {
                if (self.doc.navigation.capacity - self.doc.navigation.items.len < 2) {
                    self.doc.navigation.ensureTotalCapacityPrecise(self.doc.allocator, self.doc.nodes.capacity) catch return error.OutOfMemory;
                }
                const prev = self.doc.navigation.items[parent_idx].last_child;
                self.doc.navigation.appendAssumeCapacity(.{ .subtree_end = text_idx, .last_child = text_idx, .prev_sibling = prev });
                self.doc.navigation.appendAssumeCapacity(.{ .subtree_end = text_idx });
                self.doc.navigation.items[parent_idx].last_child = element_idx;
            }
            return true;
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
            } else scanner.findTextEnd(self.input, text_start) orelse return false;
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
            if (comptime full_navigation_index) self.doc.navigation.items[idx].subtree_end = text_idx;
            return true;
        }

        inline fn validateDeferredDtdAttributeReferences(self: *Self, input: []const u8, attr_start: usize, attr_end: usize) ParseError!void {
            if (comptime !strict_mode or expand_dtd_entities) return;
            if (self.doctype_seen and self.standalone_yes) {
                @branchHint(.cold);
                const validation: document.DtdAttributeValidation = .{
                    .input = input,
                    .attributes = .{ .start = @intCast(attr_start), .end = @intCast(attr_end) },
                };
                try document.validateDoctypeEntityConstraintsAlloc(
                    self.doc.allocator,
                    input[self.doctype_value_start..self.doctype_value_end],
                    self.require_declared_entities,
                    &validation,
                );
                self.standalone_yes = false;
            }
        }

        inline fn validateAttributeValueSpecials(self: *Self, value: []const u8, has_lt: bool, has_ampersand: bool) ParseError!void {
            if (has_lt) return error.InvalidAttributeValue;
            if (has_ampersand) {
                if (comptime !expand_dtd_entities) {
                    if (self.doctype_seen) {
                        self.standalone_yes = true;
                        return;
                    }
                }
                try document.validateXmlAttributeReferencesAlloc(self.doc.allocator, value, self.doctypeValue(), self.require_declared_entities, null);
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
        try std.testing.expectError(case.err, parseInto(&doc, case.input, .{ .mode = .strict, .validate_well_formedness = true, .validate_closing_tags = true }));
    }

    doc.clear();
    doc.source = "<r></ r>";
    try std.testing.expectError(error.InvalidClosingTagName, parseInto(&doc, doc.source, .{ .mode = .strict, .validate_well_formedness = true, .validate_closing_tags = true }));

    inline for (.{ "<r></ r>", "<r></>", "<r></r x>", "<r></r" }) |input| {
        doc.clear();
        doc.source = input;
        const result = parseInto(&doc, input, .{ .mode = .strict, .validate_well_formedness = true, .validate_closing_tags = false });
        if (std.mem.eql(u8, input, "<r></r")) {
            try std.testing.expectError(error.UnexpectedEndOfData, result);
        } else {
            try std.testing.expectError(error.InvalidClosingTagName, result);
        }
    }
}

test "compact DOM rejects element names longer than u16" {
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
    try std.testing.expectError(
        error.InputTooLarge,
        parseInto(&doc, source, .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true }),
    );
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
    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    var attrs = root.attributes();
    try std.testing.expectEqualStrings("a", (attrs.next() orelse return error.TestUnexpectedResult).nameSlice());
    try std.testing.expectEqualStrings("b", (attrs.next() orelse return error.TestUnexpectedResult).nameSlice());
    try std.testing.expect(attrs.next() == null);
}
