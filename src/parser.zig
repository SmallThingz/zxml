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
const InitialParseStackCapacity: usize = 32;
const SmallInitialNodeCapacity: usize = 64;
const LargeInitialNodeCapacity: usize = 512;
const SmallInputThreshold: usize = 4 * 1024;
const NodeDensitySampleBytes: usize = 64 * 1024;

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

pub fn parse(comptime opts: ParseOptions, allocator: std.mem.Allocator, input: opts.Input()) ParseError!opts.Document() {
    return parseTracked(opts, allocator, input, null);
}

pub fn parseDiagnostic(comptime opts: ParseOptions, allocator: std.mem.Allocator, input: opts.Input()) ?document.ParseDiagnostic {
    var error_offset: usize = 0;
    var doc = parseTracked(opts, allocator, input, &error_offset) catch |err| return .{
        .err = err,
        .offset = error_offset,
        .source = input,
    };
    doc.deinit();
    return null;
}

fn parseTracked(
    comptime opts: ParseOptions,
    allocator: std.mem.Allocator,
    input: opts.Input(),
    error_offset: ?*usize,
) ParseError!opts.Document() {
    if (error_offset) |offset| offset.* = 0;
    if (!common.lenFits(input.len)) return error.InputTooLarge;
    if (comptime opts.validate_well_formedness and opts.validate_xml_characters) {
        document.validateXmlCharacters(input) catch |err| return err;
    }

    const Doc = opts.Document();
    var doc = Doc.init(allocator);
    errdefer doc.deinit();
    doc.source = input;

    var p = Parser(opts, Doc){ .doc = &doc, .input = input, .i = 0 };
    errdefer p.nodes.deinit(allocator);
    p.parse() catch |err| {
        if (error_offset) |offset| offset.* = @min(p.i, input.len);
        return err;
    };
    doc.nodes = p.nodes.toOwnedSlice(allocator) catch return error.OutOfMemory;
    return doc;
}

fn Parser(comptime opts: ParseOptions, comptime DocType: type) type {
    const validated = opts.validate_well_formedness;
    const ValidationAttrs = if (validated) std.ArrayListUnmanaged(document.RawAttribute) else void;
    const ValidationSpan = if (validated) document.Span else void;
    const ValidationFlags = if (validated) packed struct {
        root_seen: bool = false,
        standalone_yes: bool = false,
        require_declared_entities: bool = true,
    } else void;

    return struct {
        doc: *DocType,
        input: []const u8,
        i: usize,
        nodes: std.ArrayListUnmanaged(RawNode) = .empty,
        parse_stack: std.ArrayListUnmanaged(OpenElem) = .empty,
        parse_stack_inline: [InitialParseStackCapacity]OpenElem = undefined,
        parse_attrs: ValidationAttrs = if (validated) .empty else {},
        validation_flags: ValidationFlags = if (validated) .{} else {},
        doctype_value: ValidationSpan = if (validated) .{} else {},

        const Self = @This();
        const RawNode = DocType.RawNode;
        const OpenElem = struct {
            tag_key: u64 = 0,
            idx: IndexInt,
        };

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

        inline fn initContainers(noalias self: *Self) ParseError!void {
            const initial_nodes = if (self.input.len <= SmallInputThreshold)
                SmallInitialNodeCapacity
            else blk: {
                const sample_len = @min(self.input.len, NodeDensitySampleBytes);
                const lt_count = scanner.countByte(self.input[0..sample_len], '<');
                const projected = std.math.mul(usize, lt_count, self.input.len) catch self.input.len;
                const density_estimate = projected / sample_len;
                break :blk @max(LargeInitialNodeCapacity, density_estimate + density_estimate / 8 + 1);
            };
            self.nodes.ensureTotalCapacity(self.doc.allocator, initial_nodes) catch return error.OutOfMemory;
        }

        fn parse(noalias self: *Self) align(128) ParseError!void {
            defer self.deinitParseStack();
            defer {
                if (comptime validated) self.parse_attrs.deinit(self.doc.allocator);
            }
            try self.initContainers();
            std.debug.assert(self.nodes.items.len == 0);
            _ = self.nodes.addOneAssumeCapacity();
            self.nodes.items[0] = RawNode.initDocument();
            self.parse_stack = .initBuffer(&self.parse_stack_inline);
            self.parse_stack.appendAssumeCapacity(.{ .idx = 0 });
            while (self.i + 1 < self.input.len) {
                if (self.input[self.i] != '<') {
                    if (comptime validated) {
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

            // Handle the one-byte tail outside the hot token loop. A trailing '<'
            // is malformed in validated mode and safely ignored by permissive mode;
            // any other final byte is ordinary text.
            if (self.i < self.input.len) {
                if (self.input[self.i] == '<') {
                    if (validated) return error.UnexpectedEndOfData;
                    self.i += 1;
                } else {
                    const text_start = self.i;
                    self.i = self.input.len;
                    if (comptime validated) {
                        try self.validateCharacterDataSpecials(self.input[text_start..], false, self.input[text_start] == '&');
                        if (self.topIndex() == 0 and !tables.WhitespaceTable[self.input[text_start]]) return error.InvalidDocumentContent;
                    }
                    if (!drop_whitespace_text_nodes or !tables.WhitespaceTable[self.input[text_start]]) {
                        _ = try self.appendTextNodeTo(self.topIndex(), text_start, self.input.len);
                    }
                }
            }

            if (comptime validated) {
                if (self.stackLen() > 1) return error.UnexpectedEndOfData;
                if (!self.validation_flags.root_seen) return error.ExpectedDocumentElement;
            }

            while (self.stackLen() > 1) {
                self.finishNode(self.popStack());
            }
            if (self.nodes.items.len != 0) {
                self.finishNode(0);
            }
        }

        inline fn parseOpeningTag(noalias self: *Self) ParseError!void {
            self.i += 1; // '<'

            if (self.i >= self.input.len) return error.UnexpectedEndOfData;
            if (!tables.isNameStart(self.input[self.i])) {
                if (validated) return error.ExpectedElementName;
                self.i = (scanner.findByte(self.input, self.i, '>') orelse self.input.len);
                if (self.i < self.input.len) self.i += 1;
                return;
            }

            const name_start = self.i;
            const name_scan = scanOpeningName(self.input, self.i);
            const name_end = name_scan.end;
            if (comptime validated) {
                if (name_end - name_start > std.math.maxInt(u16)) {
                    @branchHint(.unlikely);
                    return error.InputTooLarge;
                }
            }
            if (comptime validated) {
                if (name_scan.needs_unicode_validation and !document.isValidXmlNameAssumeValidUtf8(self.input[name_start..name_end])) return error.ExpectedElementName;
            }
            self.i = name_end;

            const parent_idx = self.topIndex();
            if (comptime validated) {
                if (parent_idx == 0) {
                    if (self.validation_flags.root_seen) return error.MultipleDocumentElements;
                    self.validation_flags.root_seen = true;
                }
            }
            // Common path: start tag with no attributes.
            if (self.i >= self.input.len) return error.UnexpectedEndOfData;
            const c0 = self.input[self.i];
            if (comptime validated) {
                if (c0 == '>') {
                    self.i += 1;
                    self.skipDroppedWhitespaceText();
                    if (comptime !validated) {
                        if (try self.tryAppendSimpleTextElement(parent_idx, name_start, name_end)) return;
                    }
                    const element_idx = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                    if (comptime validated) {
                        if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                    }
                    try self.pushStack(element_idx, name_scan.key);
                    return;
                }
            } else {
                if (c0 == '>') {
                    @branchHint(.likely);
                    self.i += 1;
                    self.skipDroppedWhitespaceText();
                    if (comptime !validated) {
                        if (try self.tryAppendSimpleTextElement(parent_idx, name_start, name_end)) return;
                    }
                    const element_idx = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                    if (comptime validated) {
                        if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                    }
                    try self.pushStack(element_idx, name_scan.key);
                    return;
                }
            }

            if (comptime validated) {
                if (c0 == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    self.i += 2;
                    _ = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                    return;
                }
            } else if (self.i + 1 < self.input.len) {
                const terminator_pair = std.mem.readInt(u16, self.input[self.i..][0..2], .little);
                if (terminator_pair == (@as(u16, '>') << 8 | @as(u16, '/'))) {
                    self.i += 2;
                    _ = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                    return;
                }
            }

            const attr_start = self.i;
            if (comptime !validated) {
                const tail = scanner.scanStartTagEnd(self.input, attr_start) orelse {
                    self.i = self.input.len;
                    return error.UnexpectedEndOfData;
                };

                self.i = tail.end + 1;
                if (tail.self_closing) {
                    _ = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                    return;
                }

                self.skipDroppedWhitespaceText();
                if (comptime !validated) {
                    if (try self.tryAppendSimpleTextElement(parent_idx, name_start, name_end)) return;
                }
                const element_idx = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                if (comptime validated) {
                    if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                }
                try self.pushStack(element_idx, name_scan.key);
                return;
            }
            self.parse_attrs.items.len = 0;
            while (self.i < self.input.len) {
                const boundary = self.i;
                self.skipWhitespace();
                if (self.i >= self.input.len) return error.UnexpectedEndOfData;

                const c = self.input[self.i];
                if (c == '>') {
                    const attr_end = self.i;
                    if (comptime validated) {
                        const input = self.input;
                        try self.validateDeferredDtdAttributeReferences(input, attr_start, attr_end);
                        const attrs = self.parse_attrs.items;
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
                    self.skipDroppedWhitespaceText();
                    if (comptime !validated) {
                        if (try self.tryAppendSimpleTextElement(parent_idx, name_start, name_end)) return;
                    }
                    const element_idx = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                    if (comptime validated) {
                        if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                    }
                    try self.pushStack(element_idx, name_scan.key);
                    return;
                }

                if (c == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    const attr_end = self.i;
                    if (comptime validated) {
                        const input = self.input;
                        try self.validateDeferredDtdAttributeReferences(input, attr_start, attr_end);
                        const attrs = self.parse_attrs.items;
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
                    _ = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                    return;
                }

                if (validated and self.i == boundary) {
                    @branchHint(.unlikely);
                    return error.ExpectedAttributeName;
                }
                if (!tables.isNameStart(c)) {
                    if (validated) {
                        @branchHint(.unlikely);
                        return error.ExpectedAttributeName;
                    }
                    self.i += 1;
                    continue;
                }

                const attr_name_start = self.i;
                const attr_name_needs_unicode_validation = if (comptime validated) blk: {
                    const scan = scanner.scanNameEndAfterStart(self.input, self.i);
                    self.i = scan.end;
                    break :blk scan.needs_unicode_validation;
                } else blk: {
                    self.i = scanner.findNameEnd(self.input, self.i);
                    break :blk false;
                };
                const attr_name_end = self.i;
                if (comptime validated) {
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
                            if (comptime validated) {
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
                            if (comptime validated) {
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
                            if (validated) return error.ExpectedQuote;
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

                    if (validated) {
                        @branchHint(.unlikely);
                        if (self.i >= input_len) return error.UnexpectedEndOfData;
                        return error.ExpectedEq;
                    }
                }

                if (comptime validated) {
                    const attr_len = self.parse_attrs.items.len;
                    if (attr_len == self.parse_attrs.capacity) {
                        @branchHint(.unlikely);
                        self.parse_attrs.ensureTotalCapacityPrecise(
                            self.doc.allocator,
                            attr_len +| attr_len / 2 +| @as(usize, 8),
                        ) catch return error.OutOfMemory;
                    }
                    self.parse_attrs.addOneAssumeCapacity().* = .{
                        .name = .{ .start = @intCast(attr_name_start), .end = @intCast(attr_name_end) },
                        .value = .{ .start = @intCast(value_start), .end = @intCast(value_end) },
                    };
                }
            }

            return error.UnexpectedEndOfData;
        }

        inline fn parseClosingTag(noalias self: *Self) ParseError!void {
            self.i += 2; // </

            if (self.i < self.input.len and tables.isWhitespace(self.input[self.i])) {
                if (validated) return error.InvalidClosingTagName;
                self.skipWhitespace();
            }
            if (self.i >= self.input.len) {
                if (validated) return error.UnexpectedEndOfData;
                return;
            }
            if (!tables.isNameStart(self.input[self.i])) {
                if (validated) return error.InvalidClosingTagName;
                const gt = scanner.findByte(self.input, self.i, '>') orelse {
                    self.i = self.input.len;
                    return;
                };
                self.i = gt + 1;
                return;
            }

            const close_start = self.i;
            const close_scan = scanOpeningName(self.input, close_start);
            const close_end = close_scan.end;
            if (comptime validated) {
                if (close_scan.needs_unicode_validation and !document.isValidXmlNameAssumeValidUtf8(self.input[close_start..close_end])) {
                    return error.InvalidClosingTagName;
                }
            }
            self.i = close_end;
            if (self.i < self.input.len and tables.isWhitespace(self.input[self.i])) self.skipWhitespace();
            if (self.i >= self.input.len) {
                if (validated) return error.UnexpectedEndOfData;
                return;
            }
            if (self.input[self.i] == '>') {
                self.i += 1;
            } else {
                if (validated) return error.InvalidClosingTagName;
                const gt = scanner.findByte(self.input, self.i, '>') orelse {
                    self.i = self.input.len;
                    return;
                };
                self.i = gt + 1;
            }

            if (self.stackLen() <= 1) {
                if (validated) return error.InvalidClosingTagName;
                return;
            }

            const close_name = self.input[close_start..close_end];
            const top = self.parse_stack.items[self.parse_stack.items.len - 1];
            if (self.openElemMatchesClose(top, close_name, close_scan.key)) {
                @branchHint(.likely);
                self.finishNode(self.popStack());
                return;
            }
            if (validated) return error.InvalidClosingTagName;

            // Permissive XML recovery mirrors zhtml's malformed-close strategy:
            // search only after the hot top-match misses, pop through an exact
            // case-sensitive opener when found, otherwise ignore the close.
            var pos = self.parse_stack.items.len - 1;
            var found: ?usize = null;
            while (pos > 0) {
                pos -= 1;
                if (pos == 0) break;
                if (self.openElemMatchesClose(self.parse_stack.items[pos], close_name, close_scan.key)) {
                    found = pos;
                    break;
                }
            }
            const found_pos = found orelse return;
            while (self.parse_stack.items.len > found_pos) {
                self.finishNode(self.popStack());
            }
        }

        fn parsePiOrDeclaration(noalias self: *Self) ParseError!void {
            const markup_start = self.i;
            self.i += 2; // <?

            if (self.i >= self.input.len or !tables.isNameStart(self.input[self.i])) {
                if (validated) return error.ExpectedPiTarget;
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
            const target_needs_unicode_validation = if (comptime validated) blk: {
                const scan = scanner.scanNameEndAfterStart(self.input, self.i);
                self.i = scan.end;
                break :blk scan.needs_unicode_validation;
            } else blk: {
                self.i += 1;
                self.i = scanner.findNameEnd(self.input, self.i);
                break :blk false;
            };
            const target_end = self.i;
            if (comptime validated) {
                if (target_needs_unicode_validation and !document.isValidXmlNameAssumeValidUtf8(self.input[target_start..target_end])) return error.ExpectedPiTarget;
            }
            const xml_target = target_end - target_start == 3 and
                std.ascii.eqlIgnoreCase(self.input[target_start..target_end], "xml");
            if (comptime validated) {
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
                if (validated) return error.UnexpectedEndOfData;
                self.i = self.input.len;
                return;
            };
            const value_end = end;
            self.i = end + 2;

            if (comptime validated) {
                if (xml_target) {
                    const declaration = try document.validateXmlDeclaration(self.input[value_start..value_end]);
                    self.validation_flags.standalone_yes = declaration.standalone_yes;
                }
            }

            if (!opts.include_misc_nodes) return;

            const decl = xml_target;
            const kind: NodeType = if (decl) .declaration else .pi;

            const parent_idx = self.topIndex();
            _ = try self.appendMiscNodeTo(
                parent_idx,
                kind,
                .{ .start = @intCast(target_start), .end = @intCast(target_end) },
                .{ .start = @intCast(value_start), .end = @intCast(value_end) },
            );
        }

        fn parseBangNode(noalias self: *Self) ParseError!void {
            if (self.i + 3 < self.input.len and self.input[self.i + 2] == '-' and self.input[self.i + 3] == '-') {
                const value_start = self.i + 4;
                const end = scanner.findSequence(self.input, value_start, "-->") orelse {
                    if (validated) return error.UnexpectedEndOfData;
                    self.i = self.input.len;
                    return;
                };
                if (comptime validated) try validateComment(self.input[value_start..end]);
                self.i = end + 3;

                if (!opts.include_misc_nodes) return;

                const parent_idx = self.topIndex();
                _ = try self.appendMiscNodeTo(
                    parent_idx,
                    .comment,
                    .{ .start = @intCast(value_start), .end = @intCast(end) },
                    .{},
                );
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
                    if (validated) return error.UnexpectedEndOfData;
                    self.i = self.input.len;
                    return;
                };
                self.i = end + 3;

                if (comptime validated) {
                    if (self.topIndex() == 0) return error.InvalidDocumentContent;
                }

                const parent_idx = self.topIndex();
                if (comptime opts.include_misc_nodes) {
                    _ = try self.appendMiscNodeTo(
                        parent_idx,
                        .cdata,
                        .{ .start = @intCast(value_start), .end = @intCast(end) },
                        .{},
                    );
                } else {
                    _ = try self.appendTextNodeTo(parent_idx, value_start, end);
                }
                return;
            }

            if (scanner.isDoctype(self.input, self.i)) {
                if (comptime validated) {
                    if (!scanner.isDoctypeExact(self.input, self.i)) return error.ExpectedGt;
                    if (self.topIndex() != 0 or self.validation_flags.root_seen or self.doctypeSeen()) return error.InvalidDoctype;
                }
                const j = scanner.findDoctypeEnd(self.input, self.i + 9) orelse {
                    if (validated) return error.UnexpectedEndOfData;
                    self.i = self.input.len;
                    return;
                };

                const value_start = self.i + 9;
                const value_end = j;
                if (comptime validated) {
                    const info = try document.validateDoctypeAlloc(self.doc.allocator, self.input[value_start..value_end]);
                    const require_declared_entities = self.validation_flags.standalone_yes or (!info.has_external_id and !info.has_parameter_entity_references);
                    try document.validateDoctypeEntityConstraintsAlloc(
                        self.doc.allocator,
                        self.input[value_start..value_end],
                        require_declared_entities,
                        null,
                    );
                    self.doctype_value = .{ .start = @intCast(value_start), .end = @intCast(value_end) };
                    self.validation_flags.require_declared_entities = require_declared_entities;
                    self.validation_flags.standalone_yes = false;
                }
                self.i = j + 1;

                if (expand_dtd_entities) {
                    try self.doc.registerDoctypeEntities(self.input[value_start..value_end]);
                }

                if (!opts.include_misc_nodes) return;

                const parent_idx = self.topIndex();
                _ = try self.appendMiscNodeTo(
                    parent_idx,
                    .doctype,
                    .{ .start = @intCast(value_start), .end = @intCast(value_end) },
                    .{},
                );
                return;
            }

            if (validated) return error.ExpectedGt;
            self.i = scanner.findByte(self.input, self.i, '>') orelse self.input.len;
            if (self.i < self.input.len) self.i += 1;
        }

        inline fn previousSiblingForAppend(noalias self: *Self, parent_idx: IndexInt) IndexInt {
            if (comptime !opts.store_prev_sibling) return InvalidIndex;
            const len = self.nodes.items.len;
            if (len <= 1) return InvalidIndex;
            var candidate: IndexInt = @intCast(len - 1);
            while (candidate != InvalidIndex and candidate > parent_idx) {
                const parent = self.nodes.items[candidate].parent;
                if (parent == parent_idx) return candidate;
                if (parent == InvalidIndex or parent >= candidate) return InvalidIndex;
                candidate = parent;
            }
            return InvalidIndex;
        }

        inline fn commitChildMetadata(noalias self: *Self, parent_idx: IndexInt, idx: IndexInt) void {
            if (comptime opts.store_last_child) self.nodes.items[parent_idx].last_child = idx;
        }

        inline fn ensureNodeCapacity(noalias self: *Self, needed: usize) ParseError!void {
            const len = self.nodes.items.len;
            if (self.nodes.capacity - len < needed) {
                @branchHint(.unlikely);
                const target = @max(len + needed, len +| len / 2 +| 8);
                self.nodes.ensureTotalCapacityPrecise(self.doc.allocator, target) catch return error.OutOfMemory;
            }
        }

        inline fn appendElementNodeTo(noalias self: *Self, parent_idx: IndexInt, name_start: usize, name_end: usize) ParseError!IndexInt {
            try self.ensureNodeCapacity(1);
            const idx: IndexInt = @intCast(self.nodes.items.len);
            const prev = self.previousSiblingForAppend(parent_idx);
            self.nodes.appendAssumeCapacity(RawNode.initElement(
                idx,
                parent_idx,
                .{ .start = @intCast(name_start), .end = @intCast(name_end) },
                prev,
            ));
            self.commitChildMetadata(parent_idx, idx);
            return idx;
        }

        inline fn appendTextNodeTo(noalias self: *Self, parent_idx: IndexInt, start_: usize, end_: usize) ParseError!IndexInt {
            try self.ensureNodeCapacity(1);
            const idx: IndexInt = @intCast(self.nodes.items.len);
            const prev = self.previousSiblingForAppend(parent_idx);
            self.nodes.appendAssumeCapacity(RawNode.initText(
                parent_idx,
                .{ .start = @intCast(start_), .end = @intCast(end_) },
                prev,
            ));
            self.commitChildMetadata(parent_idx, idx);
            return idx;
        }

        inline fn appendMiscNodeTo(
            noalias self: *Self,
            parent_idx: IndexInt,
            kind: NodeType,
            primary: document.Span,
            value: document.Span,
        ) ParseError!IndexInt {
            comptime std.debug.assert(opts.include_misc_nodes);
            try self.ensureNodeCapacity(1);
            const idx: IndexInt = @intCast(self.nodes.items.len);
            const prev = self.previousSiblingForAppend(parent_idx);
            self.nodes.appendAssumeCapacity(RawNode.initMisc(parent_idx, kind, primary, value, prev));
            self.commitChildMetadata(parent_idx, idx);
            return idx;
        }

        noinline fn growParseStack(noalias self: *Self) ParseError!void {
            @branchHint(.cold);
            if (self.parse_stack.capacity <= InitialParseStackCapacity) {
                var heap = std.ArrayListUnmanaged(OpenElem).initCapacity(
                    self.doc.allocator,
                    self.parse_stack.capacity * 2,
                ) catch return error.OutOfMemory;
                heap.appendSliceAssumeCapacity(self.parse_stack.items);
                self.parse_stack = heap;
                return;
            }
            self.parse_stack.ensureUnusedCapacity(self.doc.allocator, 1) catch return error.OutOfMemory;
        }

        inline fn pushStack(noalias self: *Self, idx: IndexInt, tag_key: u64) ParseError!void {
            if (self.parse_stack.items.len == self.parse_stack.capacity) {
                @branchHint(.unlikely);
                try self.growParseStack();
            }
            self.parse_stack.appendAssumeCapacity(.{ .tag_key = tag_key, .idx = idx });
        }

        inline fn popStack(noalias self: *Self) IndexInt {
            return self.parse_stack.pop().?.idx;
        }

        inline fn stackLen(self: *const Self) usize {
            return self.parse_stack.items.len;
        }

        inline fn topIndex(self: *const Self) IndexInt {
            return self.parse_stack.items[self.parse_stack.items.len - 1].idx;
        }

        inline fn openElemMatchesClose(noalias self: *const Self, open: OpenElem, close_name: []const u8, close_key: u64) bool {
            if (open.tag_key != close_key) return false;
            if (close_name.len < 8) return true;
            const open_span = self.nodes.items[open.idx].name_or_text;
            if (open_span.len() != close_name.len) return false;
            if (close_name.len == 8) return true;
            return std.mem.eql(u8, open_span.slice(self.input)[8..], close_name[8..]);
        }

        inline fn deinitParseStack(noalias self: *Self) void {
            if (self.parse_stack.capacity > InitialParseStackCapacity) self.parse_stack.deinit(self.doc.allocator);
        }

        inline fn finishNode(noalias self: *Self, idx: IndexInt) void {
            self.nodes.items[idx].subtree_end = @intCast(self.nodes.items.len - 1);
        }

        inline fn skipWhitespace(noalias self: *Self) void {
            if (self.i >= self.input.len) return;
            const c = self.input[self.i];
            if (c == ' ') {
                const next = self.i + 1;
                if (comptime validated) {
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
        ) ParseError!bool {
            comptime std.debug.assert(!validated);
            const text_start = self.i;
            if (text_start >= self.input.len or self.input[text_start] == '<') return false;

            const lt = scanner.findTextEnd(self.input, text_start) orelse return false;
            if (lt == text_start or lt + 2 >= self.input.len or self.input[lt + 1] != '/') return false;

            const close_start = lt + 2;
            const name_len = name_end - name_start;
            const close_end = close_start + name_len;
            if (close_end > self.input.len) return false;
            const open_key = scanner.prefixKey(self.input[name_start..name_end]);
            if (scanner.prefixKey(self.input[close_start..close_end]) != open_key) return false;
            if (name_len > 8 and !std.mem.eql(u8, self.input[name_start + 8 .. name_end], self.input[close_start + 8 .. close_end])) return false;

            var j = close_end;
            if (j >= self.input.len) return false;
            if (self.input[j] == '>') {
                j += 1;
            } else if (tables.isWhitespace(self.input[j])) {
                j = scanner.skipWhitespace(self.input, j);
                if (j >= self.input.len or self.input[j] != '>') return false;
                j += 1;
            } else {
                return false;
            }

            self.i = j;
            const raw = self.input[text_start..lt];
            if (drop_whitespace_text_nodes and tables.isWhitespace(raw[0]) and scanner.skipWhitespace(raw, 0) == raw.len) {
                _ = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                return true;
            }

            const element_idx = try self.appendElementNodeTo(parent_idx, name_start, name_end);
            _ = try self.appendTextNodeTo(element_idx, text_start, lt);
            self.finishNode(element_idx);
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
            const lt = if (comptime validated) blk: {
                const specials = scanner.scanTextSpecials(self.input, text_start);
                has_close_bracket = specials.has_close_bracket;
                has_ampersand = specials.has_ampersand;
                break :blk specials.lt_index;
            } else scanner.findTextEnd(self.input, text_start) orelse return false;
            if (lt >= self.input.len or lt == text_start or lt + 2 >= self.input.len or self.input[lt + 1] != '/') return false;

            const close_start = lt + 2;
            const close_end = close_start + (name_end - name_start);
            if (close_end > self.input.len) return false;
            const open_key = name_key;
            if (scanner.prefixKey(self.input[close_start..close_end]) != open_key) return false;
            if (name_end - name_start > 8 and !std.mem.eql(u8, self.input[name_start + 8 .. name_end], self.input[close_start + 8 .. close_end])) return false;

            var j = close_end;
            if (j >= self.input.len) {
                if (validated) return error.UnexpectedEndOfData;
                return false;
            }
            if (self.input[j] == '>') {
                self.i = j + 1;
            } else if (tables.isWhitespace(self.input[j])) {
                j += 1;
                while (j < self.input.len and tables.isWhitespace(self.input[j])) : (j += 1) {}
                if (j >= self.input.len) {
                    if (validated) return error.UnexpectedEndOfData;
                    return false;
                }
                if (self.input[j] != '>') return false;
                self.i = j + 1;
            } else {
                return false;
            }

            const raw = self.input[text_start..lt];
            if (comptime validated) try self.validateCharacterDataSpecials(raw, has_close_bracket, has_ampersand);
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
            _ = try self.appendTextNodeTo(idx, text_start, lt);
            self.finishNode(idx);
            return true;
        }

        inline fn validateDeferredDtdAttributeReferences(self: *Self, input: []const u8, attr_start: usize, attr_end: usize) ParseError!void {
            if (comptime !validated or expand_dtd_entities) return;
            if (self.doctypeSeen() and self.validation_flags.standalone_yes) {
                @branchHint(.cold);
                const validation: document.DtdAttributeValidation = .{
                    .input = input,
                    .attributes = .{ .start = @intCast(attr_start), .end = @intCast(attr_end) },
                };
                try document.validateDoctypeEntityConstraintsAlloc(
                    self.doc.allocator,
                    self.doctype_value.slice(input),
                    self.validation_flags.require_declared_entities,
                    &validation,
                );
                self.validation_flags.standalone_yes = false;
            }
        }

        inline fn validateAttributeValueSpecials(self: *Self, value: []const u8, has_lt: bool, has_ampersand: bool) ParseError!void {
            if (has_lt) return error.InvalidAttributeValue;
            if (has_ampersand) {
                if (comptime !expand_dtd_entities) {
                    if (self.doctypeSeen()) {
                        self.validation_flags.standalone_yes = true;
                        return;
                    }
                }
                try document.validateXmlAttributeReferencesAlloc(self.doc.allocator, value, self.doctypeValue(), self.validation_flags.require_declared_entities, null);
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
                try document.validateXmlReferencesAlloc(self.doc.allocator, value, false, self.doctypeValue(), self.validation_flags.require_declared_entities);
            }
        }

        inline fn doctypeSeen(self: *const Self) bool {
            if (comptime !validated) return false;
            return self.doctype_value.end != 0;
        }

        inline fn doctypeValue(self: *const Self) ?[]const u8 {
            if (!self.doctypeSeen()) return null;
            return self.doctype_value.slice(self.input);
        }
    };
}

test "permissive parser erases validation-only state" {
    const PermissiveDocument = document.Types(.{}).Document;
    const ValidatedDocument = document.Types(.{ .validate_well_formedness = true }).Document;
    const PermissiveParser = Parser(.{}, PermissiveDocument);
    const ValidatedParser = Parser(.{ .validate_well_formedness = true }, ValidatedDocument);

    try std.testing.expectEqual(void, @FieldType(PermissiveParser, "parse_attrs"));
    try std.testing.expectEqual(void, @FieldType(PermissiveParser, "validation_flags"));
    inline for (.{ "root_seen", "standalone_yes", "require_declared_entities" }) |field| {
        try std.testing.expect(!@hasField(PermissiveParser, field));
        try std.testing.expect(!@hasField(ValidatedParser, field));
    }
    try std.testing.expectEqual(@as(usize, 1), @sizeOf(@FieldType(ValidatedParser, "validation_flags")));
    try std.testing.expect(!@hasField(PermissiveParser, "doctype_seen"));
    try std.testing.expect(!@hasField(ValidatedParser, "doctype_seen"));
    try std.testing.expectEqual(void, @FieldType(PermissiveParser, "doctype_value"));
    try std.testing.expectEqual(document.Span, @FieldType(ValidatedParser, "doctype_value"));
    try std.testing.expect(!@hasField(PermissiveParser.OpenElem, "tag_len"));
    try std.testing.expect(!@hasField(PermissiveParser, "parse_stack_heap_owned"));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(PermissiveParser.OpenElem));
    try std.testing.expect(@sizeOf(PermissiveParser) < @sizeOf(ValidatedParser));
}

test "permissive generated DOM recovers malformed close structure" {
    const options: ParseOptions = .{};

    var mismatch = "<a><b></a>".*;
    var mismatch_doc = try options.parse(std.testing.allocator, &mismatch);
    defer mismatch_doc.deinit();
    try std.testing.expectEqual(@as(usize, 3), mismatch_doc.nodes.len);
    try std.testing.expectEqual(@as(IndexInt, 2), mismatch_doc.nodes[1].subtree_end);
    try std.testing.expectEqual(@as(IndexInt, 2), mismatch_doc.nodes[2].subtree_end);

    var unmatched = "<a></x><b/></a>".*;
    var unmatched_doc = try options.parse(std.testing.allocator, &unmatched);
    defer unmatched_doc.deinit();
    try std.testing.expectEqual(@as(usize, 3), unmatched_doc.nodes.len);
    try std.testing.expectEqual(@as(IndexInt, 2), unmatched_doc.nodes[1].subtree_end);

    var eof = "<a>".*;
    var eof_doc = try options.parse(std.testing.allocator, &eof);
    defer eof_doc.deinit();
    try std.testing.expectEqual(@as(IndexInt, 1), eof_doc.nodes[1].subtree_end);
}

test "validated generated DOM rejects malformed close structure" {
    const options: ParseOptions = .{ .validate_well_formedness = true };
    var mismatch = "<a><b></a>".*;
    try std.testing.expectError(error.InvalidClosingTagName, options.parse(std.testing.allocator, &mismatch));
    var eof = "<a>".*;
    try std.testing.expectError(error.UnexpectedEndOfData, options.parse(std.testing.allocator, &eof));
}

test "open-element key matching preserves exact name lengths" {
    const validated: ParseOptions = .{ .validate_well_formedness = true };

    var seven = "<abcdefg></abcdefg>".*;
    var seven_doc = try validated.parse(std.testing.allocator, &seven);
    seven_doc.deinit();

    var eight = "<abcdefgh></abcdefgh>".*;
    var eight_doc = try validated.parse(std.testing.allocator, &eight);
    eight_doc.deinit();

    var prefix_shorter = "<abcdefghX></abcdefgh>".*;
    try std.testing.expectError(error.InvalidClosingTagName, validated.parse(std.testing.allocator, &prefix_shorter));

    var prefix_longer = "<abcdefgh></abcdefghX>".*;
    try std.testing.expectError(error.InvalidClosingTagName, validated.parse(std.testing.allocator, &prefix_longer));

    var different_tail = "<abcdefghX></abcdefghY>".*;
    try std.testing.expectError(error.InvalidClosingTagName, validated.parse(std.testing.allocator, &different_tail));

    const permissive: ParseOptions = .{};
    var recovered = "<abcdefghX><child/></abcdefgh><tail/></abcdefghX>".*;
    var recovered_doc = try permissive.parse(std.testing.allocator, &recovered);
    defer recovered_doc.deinit();
    try std.testing.expectEqual(@as(usize, 4), recovered_doc.nodes.len);
    try std.testing.expectEqual(@as(IndexInt, 1), recovered_doc.nodes[3].parent);
}

test "open-element stack spills beyond inline capacity" {
    const options: ParseOptions = .{};
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(std.testing.allocator);
    for (0..80) |_| try source.appendSlice(std.testing.allocator, "<a>");
    try source.appendSlice(std.testing.allocator, "x");
    for (0..80) |_| try source.appendSlice(std.testing.allocator, "</a>");

    var doc = try options.parse(std.testing.allocator, source.items);
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 82), doc.nodes.len);
    try std.testing.expectEqual(@as(IndexInt, 81), doc.nodes[1].subtree_end);
}

test "generated parse builds a minimal DOM and enforces validated closing tags" {
    const options: ParseOptions = .{ .validate_well_formedness = true };
    var ok = "<root><child>v</child></root>".*;
    var doc = try options.parse(std.testing.allocator, &ok);
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 4), doc.nodes.len);
    try std.testing.expectEqualStrings("root", doc.nodeAt(1).?.nameSlice());
    try std.testing.expectEqualStrings("child", doc.nodeAt(2).?.nameSlice());
    try std.testing.expectEqualStrings("v", doc.nodeAt(3).?.valueRawSlice());

    var bad = "<root><child></root>".*;
    try std.testing.expectError(error.InvalidClosingTagName, options.parse(std.testing.allocator, &bad));
}

test "one-byte parser tails preserve validated and permissive behavior" {
    const permissive: ParseOptions = .{};
    const validated: ParseOptions = .{ .validate_well_formedness = true };

    var lone_lt = "<".*;
    var lt_doc = try permissive.parse(std.testing.allocator, &lone_lt);
    defer lt_doc.deinit();
    try std.testing.expectEqual(@as(usize, 1), lt_doc.nodes.len);

    lone_lt = "<".*;
    try std.testing.expectError(error.UnexpectedEndOfData, validated.parse(std.testing.allocator, &lone_lt));

    var lone_text = "x".*;
    var text_doc = try permissive.parse(std.testing.allocator, &lone_text);
    defer text_doc.deinit();
    try std.testing.expectEqual(@as(usize, 2), text_doc.nodes.len);
    try std.testing.expectEqualStrings("x", text_doc.nodeAt(1).?.valueRawSlice());

    lone_text = "x".*;
    try std.testing.expectError(error.InvalidDocumentContent, validated.parse(std.testing.allocator, &lone_text));

    var lone_space = " ".*;
    var space_doc = try permissive.parse(std.testing.allocator, &lone_space);
    defer space_doc.deinit();
    try std.testing.expectEqual(@as(usize, 1), space_doc.nodes.len);
}

test "validated start-tag grammar rejects malformed attributes" {
    const options: ParseOptions = .{ .validate_well_formedness = true };
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
        const input = try std.testing.allocator.dupe(u8, case.input);
        defer std.testing.allocator.free(input);
        try std.testing.expectError(case.err, options.parse(std.testing.allocator, input));
    }

    var spaced_close = "<r></ r>".*;
    try std.testing.expectError(error.InvalidClosingTagName, options.parse(std.testing.allocator, &spaced_close));
    inline for (.{ "<r></ r>", "<r></>", "<r></r x>", "<r></r" }) |literal| {
        var input = literal.*;
        const result = options.parse(std.testing.allocator, &input);
        if (std.mem.eql(u8, &input, "<r></r"))
            try std.testing.expectError(error.UnexpectedEndOfData, result)
        else
            try std.testing.expectError(error.InvalidClosingTagName, result);
    }
}

test "full validation rejects element names longer than u16" {
    const validated: ParseOptions = .{ .validate_well_formedness = true };
    const permissive: ParseOptions = .{};
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

    try std.testing.expectError(error.InputTooLarge, validated.parse(std.testing.allocator, source));
    var doc = try permissive.parse(std.testing.allocator, source);
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 2), doc.nodes.len);
}

test "permissive closing fast paths preserve permissive fallback forms" {
    const options: ParseOptions = .{};
    const Case = struct { source: []const u8, child: []const u8 };
    inline for ([_]Case{
        .{ .source = "<r><x></y></r>", .child = "x" },
        .{ .source = "<r><child></x></r>", .child = "child" },
        .{ .source = "<r><x></x \n></r>", .child = "x" },
        .{ .source = "<r><x></></r>", .child = "x" },
        .{ .source = "<r><x>t</y></r>", .child = "x" },
        .{ .source = "<r><child>t</x></r>", .child = "child" },
        .{ .source = "<r><x>t</x \n></r>", .child = "x" },
    }) |case| {
        const source = try std.testing.allocator.dupe(u8, case.source);
        defer std.testing.allocator.free(source);
        var doc = try options.parse(std.testing.allocator, source);
        defer doc.deinit();
        try std.testing.expectEqualStrings("r", doc.nodeAt(1).?.nameSlice());
        try std.testing.expectEqualStrings(case.child, doc.nodeAt(2).?.nameSlice());
    }
}

test "permissive mode accepts mixed XML whitespace around attribute equals" {
    const options: ParseOptions = .{};
    var source = "<r a \n \t=\r '1' b \r\n = \t\"2\"></r \n>".*;
    var doc = try options.parse(std.testing.allocator, &source);
    defer doc.deinit();
    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("1", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("2", root.getAttributeValueRaw("b").?);
}

test "validated start tags accept mixed XML whitespace between attributes" {
    const options: ParseOptions = .{ .validate_well_formedness = true };
    var source = "<r \n\t a='1' \r\n b=\"2\">x</r>".*;
    var doc = try options.parse(std.testing.allocator, &source);
    defer doc.deinit();
    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    var attrs = root.attributes();
    try std.testing.expectEqualStrings("a", (attrs.next() orelse return error.TestUnexpectedResult).nameSlice());
    try std.testing.expectEqualStrings("b", (attrs.next() orelse return error.TestUnexpectedResult).nameSlice());
    try std.testing.expect(attrs.next() == null);
}
