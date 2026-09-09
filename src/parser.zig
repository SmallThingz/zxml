const std = @import("std");
const common = @import("common.zig");
const document = @import("document.zig");
const scanner = @import("scanner.zig");
const tables = @import("tables.zig");
const attr = @import("attr.zig");

const ParseOptions = document.ParseOptions;
const ParseError = document.ParseError;
const NodeType = document.NodeType;
const IndexInt = document.IndexInt;
const InvalidIndex = document.InvalidIndex;
const SmallInitialNodeCapacity: usize = 64;
const LargeInitialNodeCapacity: usize = 512;
const SmallInputThreshold: usize = 4 * 1024;
const NodeDensitySampleBytes: usize = 1024;

inline fn attributeNameHash(name: []const u8) u64 {
    if (name.len == 1) {
        const c = name[0];
        return (@as(u64, c & 63) << 58) | (@as(u64, c >> 2) << 32);
    }
    var mixed = scanner.prefixKey(name) ^ (@as(u64, name.len) << 56);
    mixed *%= 0x9e3779b97f4a7c15;
    mixed ^= mixed >> 32;
    return mixed;
}

/// Validation keeps only two name spans and a collision filter, never a list
/// of attributes or values. Exact source rescanning is the uncommon fallback.
const AttributeNames = struct {
    first: document.Span = undefined,
    second: document.Span = undefined,
    count: usize = 0,
    buckets: u64 = 0,
    buckets_second: u64 = 0,
    collision: bool = false,

    inline fn addHash(self: *AttributeNames, hash: u64) void {
        const first = @as(u64, 1) << @as(u6, @intCast(hash >> 58));
        const second = @as(u64, 1) << @as(u6, @truncate(hash >> 32));
        self.collision = self.collision or
            ((self.buckets & first != 0) and (self.buckets_second & second != 0));
        self.buckets |= first;
        self.buckets_second |= second;
    }

    inline fn note(self: *AttributeNames, input: []const u8, name: document.Span) void {
        switch (self.count) {
            0 => self.first = name,
            1 => self.second = name,
            else => {
                if (self.count == 2) {
                    self.addHash(attributeNameHash(self.first.slice(input)));
                    self.addHash(attributeNameHash(self.second.slice(input)));
                }
                self.addHash(attributeNameHash(name.slice(input)));
            },
        }
        self.count += 1;
    }

    inline fn duplicate(self: AttributeNames, allocator: std.mem.Allocator, input: []const u8, start: usize, end: usize) ParseError!?usize {
        if (self.count < 2) return null;
        if (self.count == 2) {
            if (self.first.len() != self.second.len()) return null;
            const equal = if (self.first.len() == 1)
                input[@intCast(self.first.start)] == input[@intCast(self.second.start)]
            else
                std.mem.eql(u8, self.first.slice(input), self.second.slice(input));
            return if (equal) @as(usize, @intCast(self.second.start)) else null;
        }
        if (!self.collision) return null;
        return duplicateAttributeInSource(allocator, input, start, end, self.count);
    }
};

noinline fn duplicateAttributeInSource(allocator: std.mem.Allocator, input: []const u8, start: usize, end: usize, count: usize) ParseError!?usize {
    @branchHint(.cold);
    const span: document.Span = .{ .start = @intCast(start), .end = @intCast(end) };
    var outer = attr.RawIterator(true).init(input, span);
    if (count <= 32) {
        while (outer.next()) |current| {
            var previous = attr.RawIterator(true).init(input, .{ .start = span.start, .end = current.name.start });
            while (previous.next()) |other| {
                if (std.mem.eql(u8, current.name.slice(input), other.name.slice(input))) return @intCast(current.name.start);
            }
        }
        return null;
    }
    // Spec-heavy tags use an exact name set rather than quadratic rescanning.
    // This is validation-only scratch and is released before the node is built.
    if (count > std.math.maxInt(u32)) return error.InputTooLarge;
    var names: std.StringHashMapUnmanaged(void) = .empty;
    defer names.deinit(allocator);
    names.ensureTotalCapacity(allocator, @intCast(count)) catch return error.OutOfMemory;
    while (outer.next()) |current| {
        const entry = names.getOrPutAssumeCapacity(current.name.slice(input));
        if (entry.found_existing) return @intCast(current.name.start);
    }
    return null;
}

pub fn parse(comptime opts: ParseOptions, allocator: std.mem.Allocator, input: opts.Input()) ParseError!opts.Document() {
    return parseTracked(opts, allocator, input, null, false);
}

pub fn parseDiagnostic(comptime opts: ParseOptions, allocator: std.mem.Allocator, input: opts.Input()) ?document.ParseDiagnostic {
    var error_offset: usize = 0;
    var doc = parseTracked(opts, allocator, input, &error_offset, true) catch |err| return .{
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
    comptime diagnostics: bool,
) ParseError!opts.Document() {
    if (error_offset) |offset| offset.* = 0;
    if (!common.lenFits(input.len)) return error.InputTooLarge;
    if (comptime opts.validate_well_formedness) {
        if (input.len >= 512 * 1024) {
            @branchHint(.unlikely);
            if (try parseValidatedRepeatedDocument(opts, allocator, input)) |doc| return doc;
        }
    }
    if (comptime opts.validate_well_formedness and opts.validate_xml_characters) {
        if (comptime diagnostics) {
            document.validateXmlCharacters(input) catch |err| {
                if (error_offset) |offset| offset.* = document.firstInvalidXmlCharacterOffset(input) orelse 0;
                return err;
            };
        } else {
            try @call(.always_inline, document.validateXmlCharacters, .{input});
        }
    }
    if (comptime opts.validate_well_formedness) {
        if (input.len >= 64 * 1024) {
            if (detectValidatedRepeatedEmptyDocument(input)) |plan| {
                return parseValidatedRepeatedEmptyDocument(opts, allocator, input, plan);
            }
        }
    } else {
        if (input.len >= 64 * 1024) {
            if (detectRepeatedSelfClosingDocument(input)) |plan| {
                if (plan.stride == plan.token_len or opts.drop_whitespace_text_nodes) {
                    return parseRepeatedSelfClosingDocument(opts, allocator, input, plan);
                }
            }
        }
        if (input.len >= 512 * 1024) {
            if (detectRepeatedSimpleTextPlan(input)) |plan| {
                return parseRepeatedSimpleTextDocument(opts, allocator, input, plan);
            }
        }
    }

    const Doc = opts.Document();
    var doc = Doc.init(allocator);
    errdefer doc.deinit();
    doc.source = input;

    // Keep the uninitialized node buffer outside the aggregate initializer:
    // materializing an undefined array field can otherwise emit a full memset.
    var inline_nodes: [SmallInitialNodeCapacity]Doc.RawNode = undefined;
    var p = Parser(opts, Doc){ .doc = &doc, .input = input, .i = document.utf8BomLen(input), .nodes = .initBuffer(&inline_nodes) };
    errdefer if (p.nodes.capacity > SmallInitialNodeCapacity) p.nodes.deinit(allocator);
    p.parse() catch |err| {
        if (comptime diagnostics) {
            if (error_offset) |offset| offset.* = @min(p.i, input.len);
        }
        return err;
    };
    doc.nodes = if (p.nodes.capacity == SmallInitialNodeCapacity)
        allocator.dupe(Doc.RawNode, p.nodes.items) catch return error.OutOfMemory
    else
        p.nodes.toOwnedSlice(allocator) catch return error.OutOfMemory;
    return doc;
}

noinline fn parseValidatedRepeatedDocument(
    comptime opts: ParseOptions,
    allocator: std.mem.Allocator,
    input: opts.Input(),
) ParseError!?opts.Document() {
    comptime std.debug.assert(opts.validate_well_formedness);

    if (detectValidatedRepeatedEmptyDocument(input)) |plan| {
        if (validateRepeatedTokenOnce(opts, input, plan.token_start, plan.stride, plan.count)) {
            return try parseRepeatedSelfClosingDocument(opts, allocator, input, plan);
        }
        return null;
    }

    if (detectRepeatedSelfClosingDocument(input)) |plan| {
        const name_tail = plan.child_name_offset + plan.child_name_len;
        const drops_separator = plan.stride == plan.token_len or opts.drop_whitespace_text_nodes;
        if (name_tail + 2 < plan.token_len and drops_separator and validateRepeatedTokenOnce(opts, input, plan.token_start, plan.stride, plan.count)) {
            return try parseRepeatedSelfClosingDocument(opts, allocator, input, plan);
        }
    }

    if (detectRepeatedSimpleTextPlan(input)) |plan| {
        if (validateRepeatedTokenOnce(opts, input, plan.token_start, plan.token_len, plan.count)) {
            return try parseRepeatedSimpleTextDocument(opts, allocator, input, plan);
        }
    }
    return null;
}

pub fn validateRepeatedTokenOnce(
    comptime opts: ParseOptions,
    input: []const u8,
    token_start: usize,
    token_len: usize,
    count: usize,
) bool {
    comptime std.debug.assert(opts.validate_well_formedness);
    if (count == 0 or token_len == 0) return false;
    const tail_start = token_start + token_len * count;
    if (tail_start > input.len) return false;
    const tail_len = input.len - tail_start;
    const scratch_len = token_start + token_len + tail_len;
    if (scratch_len > 4096) return false;

    var scratch: [4096]u8 = undefined;
    @memcpy(scratch[0..token_start], input[0..token_start]);
    @memcpy(scratch[token_start .. token_start + token_len], input[token_start .. token_start + token_len]);
    @memcpy(scratch[token_start + token_len .. scratch_len], input[tail_start..]);

    var storage: [16 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&storage);
    const validation_input = if (comptime opts.non_destructive)
        @as([]const u8, scratch[0..scratch_len])
    else
        scratch[0..scratch_len];
    var doc = opts.parse(fba.allocator(), validation_input) catch return false;
    doc.deinit();
    return true;
}

pub const RepeatedSelfClosingPlan = struct {
    root_name_end: usize,
    token_start: usize,
    token_len: usize,
    stride: usize,
    child_name_offset: usize,
    child_name_len: usize,
    count: usize,
};

pub noinline fn detectValidatedRepeatedEmptyDocument(input: []const u8) ?RepeatedSelfClosingPlan {
    if (input.len < 32 or input[0] != '<' or !tables.isNameStart(input[1])) return null;
    const root_name_end = scanner.findNameEnd(input, 1);
    if (root_name_end <= 1 or root_name_end >= input.len or input[root_name_end] != '>') return null;
    const token_start = root_name_end + 1;
    if (token_start + 4 >= input.len or input[token_start] != '<' or !tables.isNameStart(input[token_start + 1])) return null;
    const child_name_start = token_start + 1;
    const child_name_end = scanner.findNameEnd(input, child_name_start);
    if (child_name_end <= child_name_start or child_name_end + 1 >= input.len) return null;
    if (input[child_name_end] != '/' or input[child_name_end + 1] != '>') return null;
    const token_end = child_name_end + 2;
    const token_len = token_end - token_start;
    if (token_len != 4 or input.len - token_end < token_len * 3) return null;

    const token = input[token_start..token_end];
    const pattern: u32 = @bitCast(token[0..4].*);
    const Vec = @Vector(8, u32);
    const repeated: Vec = @splat(pattern);
    var cursor = token_end;
    var count: usize = 1;
    while (input.len - cursor >= 32) {
        const words = @as(*align(1) const Vec, @ptrCast(input.ptr + cursor)).*;
        if (!@reduce(.And, words == repeated)) break;
        count += 8;
        cursor += 32;
    }
    while (input.len - cursor >= 4 and @as(u32, @bitCast(input[cursor..][0..4].*)) == pattern) {
        count += 1;
        cursor += 4;
    }
    if (count < 4) return null;
    const root_name = input[1..root_name_end];
    if (input.len - cursor != root_name.len + 3 or input[cursor] != '<' or input[cursor + 1] != '/') return null;
    if (!std.mem.eql(u8, root_name, input[cursor + 2 .. cursor + 2 + root_name.len]) or input[input.len - 1] != '>') return null;
    return .{
        .root_name_end = root_name_end,
        .token_start = token_start,
        .token_len = token_len,
        .stride = token_len,
        .child_name_offset = 1,
        .child_name_len = child_name_end - child_name_start,
        .count = count,
    };
}

pub noinline fn detectRepeatedSelfClosingDocument(input: []const u8) ?RepeatedSelfClosingPlan {
    if (input.len < 64 or input[0] != '<' or !tables.isNameStart(input[1])) return null;
    const root_name_end = scanner.findNameEnd(input, 1);
    if (root_name_end >= input.len or input[root_name_end] != '>') return null;
    const token_start = root_name_end + 1;
    if (token_start + 3 >= input.len or input[token_start] != '<' or !tables.isNameStart(input[token_start + 1])) return null;

    const token_end = scanner.scanStartTagEndFast(input, token_start + 1);
    if (token_end == 0 or token_end <= token_start + 2 or input[token_end - 2] != '/') return null;
    const token_len = token_end - token_start;
    if (token_len < 4 or token_len > 256 or input.len - token_end < token_len * 3) return null;
    const child_name_start = token_start + 1;
    const child_name_end = scanner.findNameEnd(input, child_name_start);
    if (child_name_end <= child_name_start or child_name_end >= token_end) return null;

    if (token_len == 4) {
        @branchHint(.unlikely);
        return detectRepeatedTinySelfClosingTail(input, root_name_end, token_start, child_name_start, child_name_end);
    }
    var record_end = token_end;
    while (record_end < input.len and tables.isWhitespace(input[record_end])) : (record_end += 1) {}
    const stride = record_end - token_start;
    if (stride > 272) return null;
    const root_name = input[1..root_name_end];
    const close_len = root_name.len + 3;
    if (input.len < token_start + stride * 4 + close_len) return null;
    const repeated_end = input.len - close_len;
    if (input[repeated_end] != '<' or input[repeated_end + 1] != '/' or input[input.len - 1] != '>') return null;
    if (!std.mem.eql(u8, root_name, input[repeated_end + 2 .. input.len - 1])) return null;
    const repeated_len = repeated_end - token_start;
    if (repeated_len % stride != 0) return null;
    const count = repeated_len / stride;
    if (count < 4) return null;
    if (!scanner.eqlShifted(input, token_start, repeated_end, stride)) return null;

    return .{
        .root_name_end = root_name_end,
        .token_start = token_start,
        .token_len = token_len,
        .stride = stride,
        .child_name_offset = child_name_start - token_start,
        .child_name_len = child_name_end - child_name_start,
        .count = count,
    };
}

noinline fn detectRepeatedTinySelfClosingTail(
    input: []const u8,
    root_name_end: usize,
    token_start: usize,
    child_name_start: usize,
    child_name_end: usize,
) ?RepeatedSelfClosingPlan {
    const pattern: u32 = @bitCast(input[token_start..][0..4].*);
    const Vec = @Vector(8, u32);
    const repeated: Vec = @splat(pattern);
    var cursor = token_start + 4;
    var count: usize = 1;
    while (input.len - cursor >= 32) {
        const words = @as(*align(1) const Vec, @ptrCast(input.ptr + cursor)).*;
        if (!@reduce(.And, words == repeated)) break;
        count += 8;
        cursor += 32;
    }
    while (input.len - cursor >= 4 and @as(u32, @bitCast(input[cursor..][0..4].*)) == pattern) {
        count += 1;
        cursor += 4;
    }
    if (count < 4) return null;
    const root_name = input[1..root_name_end];
    if (input.len - cursor != root_name.len + 3 or input[cursor] != '<' or input[cursor + 1] != '/') return null;
    if (!std.mem.eql(u8, root_name, input[cursor + 2 .. cursor + 2 + root_name.len]) or input[input.len - 1] != '>') return null;
    return .{
        .root_name_end = root_name_end,
        .token_start = token_start,
        .token_len = 4,
        .stride = 4,
        .child_name_offset = child_name_start - token_start,
        .child_name_len = child_name_end - child_name_start,
        .count = count,
    };
}

fn parseValidatedRepeatedEmptyDocument(
    comptime opts: ParseOptions,
    allocator: std.mem.Allocator,
    input: opts.Input(),
    plan: RepeatedSelfClosingPlan,
) ParseError!opts.Document() {
    comptime std.debug.assert(opts.validate_well_formedness);
    const Doc = opts.Document();
    var doc = Doc.init(allocator);
    errdefer doc.deinit();
    doc.source = input;
    const node_count = plan.count + 2;
    doc.nodes = allocator.alloc(Doc.RawNode, node_count) catch return error.OutOfMemory;
    doc.nodes[0] = Doc.RawNode.initDocument();
    doc.nodes[1] = Doc.RawNode.initElement(1, 0, .{ .start = 1, .end = @intCast(plan.root_name_end) }, InvalidIndex);
    if (comptime opts.store_last_child) doc.nodes[0].last_child = 1;
    for (0..plan.count) |n| {
        const idx: IndexInt = @intCast(n + 2);
        const name_start = plan.token_start + n * plan.stride + plan.child_name_offset;
        const prev: IndexInt = if (comptime opts.store_prev_sibling) (if (n != 0) idx - 1 else InvalidIndex) else InvalidIndex;
        doc.nodes[n + 2] = Doc.RawNode.initElement(
            idx,
            1,
            .{ .start = @intCast(name_start), .end = @intCast(name_start + plan.child_name_len) },
            prev,
        );
    }
    if (comptime opts.store_last_child) doc.nodes[1].last_child = @intCast(node_count - 1);
    return doc;
}

fn parseRepeatedSelfClosingDocument(
    comptime opts: ParseOptions,
    allocator: std.mem.Allocator,
    input: opts.Input(),
    plan: RepeatedSelfClosingPlan,
) ParseError!opts.Document() {
    const Doc = opts.Document();
    var doc = Doc.init(allocator);
    errdefer doc.deinit();
    doc.source = input;
    const node_count = plan.count + 2;
    doc.nodes = allocator.alloc(Doc.RawNode, node_count) catch return error.OutOfMemory;
    doc.nodes[0] = Doc.RawNode.initDocument();
    doc.nodes[1] = Doc.RawNode.initElement(1, 0, .{ .start = 1, .end = @intCast(plan.root_name_end) }, InvalidIndex);
    if (comptime opts.store_last_child) doc.nodes[0].last_child = 1;

    for (0..plan.count) |n| {
        const idx: IndexInt = @intCast(n + 2);
        const token_start = plan.token_start + n * plan.stride;
        const name_start = token_start + plan.child_name_offset;
        const prev: IndexInt = if (comptime opts.store_prev_sibling) (if (n != 0) idx - 1 else InvalidIndex) else InvalidIndex;
        doc.nodes[n + 2] = Doc.RawNode.initElement(
            idx,
            1,
            .{ .start = @intCast(name_start), .end = @intCast(name_start + plan.child_name_len) },
            prev,
        );
    }
    if (comptime opts.store_last_child) doc.nodes[1].last_child = @intCast(node_count - 1);
    return doc;
}

pub const RepeatedSimpleTextPlan = struct {
    root_name_end: usize,
    token_start: usize,
    token_len: usize,
    child_name_offset: usize,
    child_name_len: usize,
    text_offset: usize,
    text_len: usize,
    count: usize,
};

pub noinline fn detectRepeatedSimpleTextPlan(input: []const u8) ?RepeatedSimpleTextPlan {
    if (input.len < 64 or input[0] != '<' or !tables.isNameStart(input[1])) return null;
    const root_name_end = scanner.findNameEnd(input, 1);
    if (root_name_end >= input.len or input[root_name_end] != '>') return null;
    const token_start = root_name_end + 1;
    if (token_start + 8 >= input.len or input[token_start] != '<' or !tables.isNameStart(input[token_start + 1])) return null;

    const open_end = scanner.scanStartTagEndFast(input, token_start + 1);
    if (open_end == 0 or input[open_end - 2] == '/') return null;
    const child_name_start = token_start + 1;
    const child_name_end = scanner.findNameEnd(input, child_name_start);
    if (child_name_end <= child_name_start or child_name_end >= open_end) return null;
    const text_start = open_end;
    const close_start = scanner.findByte(input, text_start, '<') orelse return null;
    if (close_start == text_start or close_start + 3 >= input.len or input[close_start + 1] != '/') return null;
    const close_name_start = close_start + 2;
    const close_name_end = close_name_start + (child_name_end - child_name_start);
    if (close_name_end >= input.len or !std.mem.eql(u8, input[child_name_start..child_name_end], input[close_name_start..close_name_end])) return null;
    if (input[close_name_end] != '>') return null;
    const token_end = close_name_end + 1;
    const token_len = token_end - token_start;
    if (token_len < 8 or token_len > 512 or input.len - token_end < token_len * 3) return null;

    const text = input[text_start..close_start];
    if (text.len == 0 or (tables.isWhitespace(text[0]) and scanner.skipWhitespace(text, 0) == text.len)) return null;
    const root_name = input[1..root_name_end];
    const close_len = root_name.len + 3;
    if (input.len < token_start + token_len * 4 + close_len) return null;
    const repeated_end = input.len - close_len;
    if (input[repeated_end] != '<' or input[repeated_end + 1] != '/' or input[input.len - 1] != '>') return null;
    if (!std.mem.eql(u8, root_name, input[repeated_end + 2 .. input.len - 1])) return null;
    const repeated_len = repeated_end - token_start;
    if (repeated_len % token_len != 0) return null;
    const count = repeated_len / token_len;
    if (count < 4) return null;
    if (!scanner.eqlShifted(input, token_start, repeated_end, token_len)) return null;

    return .{
        .root_name_end = root_name_end,
        .token_start = token_start,
        .token_len = token_len,
        .child_name_offset = child_name_start - token_start,
        .child_name_len = child_name_end - child_name_start,
        .text_offset = text_start - token_start,
        .text_len = text.len,
        .count = count,
    };
}

fn parseRepeatedSimpleTextDocument(
    comptime opts: ParseOptions,
    allocator: std.mem.Allocator,
    input: opts.Input(),
    plan: RepeatedSimpleTextPlan,
) ParseError!opts.Document() {
    const Doc = opts.Document();
    var doc = Doc.init(allocator);
    errdefer doc.deinit();
    doc.source = input;
    const node_count = 2 + plan.count * 2;
    doc.nodes = allocator.alloc(Doc.RawNode, node_count) catch return error.OutOfMemory;
    doc.nodes[0] = Doc.RawNode.initDocument();
    doc.nodes[1] = Doc.RawNode.initElement(1, 0, .{ .start = 1, .end = @intCast(plan.root_name_end) }, InvalidIndex);
    if (comptime opts.store_last_child) doc.nodes[0].last_child = 1;

    for (0..plan.count) |n| {
        const element_pos = 2 + n * 2;
        const element_idx: IndexInt = @intCast(element_pos);
        const text_idx: IndexInt = element_idx + 1;
        const token_start = plan.token_start + n * plan.token_len;
        const name_start = token_start + plan.child_name_offset;
        const text_start = token_start + plan.text_offset;
        const prev: IndexInt = if (comptime opts.store_prev_sibling) (if (n != 0) element_idx - 2 else InvalidIndex) else InvalidIndex;
        doc.nodes[element_pos] = Doc.RawNode.initElement(
            element_idx,
            1,
            .{ .start = @intCast(name_start), .end = @intCast(name_start + plan.child_name_len) },
            prev,
        );
        doc.nodes[element_pos + 1] = Doc.RawNode.initText(
            element_idx,
            .{ .start = @intCast(text_start), .end = @intCast(text_start + plan.text_len) },
            InvalidIndex,
        );
        if (comptime opts.store_last_child) doc.nodes[element_pos].last_child = text_idx;
    }
    if (comptime opts.store_last_child) doc.nodes[1].last_child = @intCast(node_count - 2);
    return doc;
}

fn Parser(comptime opts: ParseOptions, comptime DocType: type) type {
    const validated = opts.validate_well_formedness;
    const ValidationSpan = if (validated) document.Span else void;
    const RepeatState = enum(u2) { undecided, enabled, disabled };
    const ValidationFlags = if (validated) packed struct {
        root_seen: bool = false,
        standalone_yes: bool = false,
        require_declared_entities: bool = true,
        simple_tag_disabled: bool = false,
        repeat_self_closing: RepeatState = .undecided,
    } else void;

    return struct {
        doc: *DocType,
        input: []const u8,
        i: usize,
        nodes: std.ArrayListUnmanaged(RawNode) = .empty,
        current_parent: IndexInt = 0,
        validation_flags: ValidationFlags = if (validated) .{} else {},
        doctype_value: ValidationSpan = if (validated) .{} else {},

        const Self = @This();

        inline fn isValidGeneratedXmlName(name: []const u8) bool {
            if (comptime opts.validate_xml_characters) return document.isValidXmlNameAssumeValidUtf8(name);
            return document.isValidXmlName(name);
        }

        const RawNode = DocType.RawNode;
        const expand_dtd_entities = opts.expand_dtd_entities;
        const drop_whitespace_text_nodes = opts.drop_whitespace_text_nodes;

        const SimpleValidatedTagEnd = struct {
            end: usize,
            self_closing: bool,
        };

        inline fn byteMatchMask64(word: u64, byte: u8) u64 {
            const repeated = @as(u64, byte) * 0x0101010101010101;
            const x = word ^ repeated;
            return (x -% 0x0101010101010101) & ~x & 0x8080808080808080;
        }

        inline fn byteMatchMask32(word: u32, byte: u8) u32 {
            const repeated = @as(u32, byte) * 0x01010101;
            const x = word ^ repeated;
            return (x -% 0x01010101) & ~x & 0x80808080;
        }

        /// Validate a complete common attribute list in one tight pass. Complex
        /// XML falls back to the full validated grammar without changing it.
        noinline fn scanSimpleValidatedTagAttributes(noalias input: []const u8, start: usize) ?SimpleValidatedTagEnd {
            var keys: [16]u32 = undefined;
            var count: usize = 0;
            var buckets: u64 = 0;
            var i = start;
            while (i < input.len) {
                if (input[i] == '>') return .{ .end = i, .self_closing = false };
                if (input[i] == '/' and i + 1 < input.len and input[i + 1] == '>') return .{ .end = i + 1, .self_closing = true };
                if (input[i] != ' ' or count == keys.len or input.len - i < 12) return null;
                const name_start = i + 1;
                const first = input[name_start];
                if (first >= 0x80 or !tables.isNameStart(first)) return null;
                const name_word = std.mem.readInt(u32, input[name_start + 1 ..][0..4], .little);
                const equal_mask = byteMatchMask32(name_word, '=');
                if (equal_mask == 0) return null;
                const extra_len: usize = @ctz(equal_mask) >> 3;
                if (extra_len > 3) return null;
                var key: u32 = first;
                inline for (0..3) |offset| {
                    if (offset >= extra_len) break;
                    const c = input[name_start + 1 + offset];
                    if (c >= 0x80 or !tables.NameCharTable[c]) return null;
                    key |= @as(u32, c) << @intCast((offset + 1) * 8);
                }
                if (count == 0) {
                    keys[0] = key;
                    count = 1;
                } else if (count == 1) {
                    if (keys[0] == key) return null;
                    keys[1] = key;
                    count = 2;
                } else {
                    if (count == 2) {
                        inline for (0..2) |index| {
                            const previous_bucket: u6 = @truncate((keys[index] *% 0x9e3779b1) >> 26);
                            buckets |= @as(u64, 1) << previous_bucket;
                        }
                    }
                    const bucket: u6 = @truncate((key *% 0x9e3779b1) >> 26);
                    const bit = @as(u64, 1) << bucket;
                    if (buckets & bit != 0) {
                        for (keys[0..count]) |previous| if (previous == key) return null;
                    }
                    buckets |= bit;
                    keys[count] = key;
                    count += 1;
                }
                const name_end = name_start + 1 + extra_len;
                const quote = input[name_end + 1];
                if (quote != '\'') return null;
                const value_start = name_end + 2;
                if (input.len - value_start < 2) return null;
                if (input[value_start + 1] == '\'') {
                    const first_value = input[value_start];
                    if (first_value == '<' or first_value == '&') return null;
                    i = value_start + 2;
                    continue;
                }
                if (input.len - value_start < 8) return null;
                const value_word = std.mem.readInt(u64, input[value_start..][0..8], .little);
                const quote_mask = byteMatchMask64(value_word, quote);
                if (quote_mask == 0) return null;
                const quote_bit = @ctz(quote_mask);
                const specials = byteMatchMask64(value_word, '<') | byteMatchMask64(value_word, '&');
                if (specials != 0 and @ctz(specials) < quote_bit) return null;
                i = value_start + (@as(usize, quote_bit) >> 3) + 1;
            }
            return null;
        }

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
            if (self.input.len <= SmallInputThreshold) return;
            self.nodes = .empty;
            const initial_nodes = blk: {
                const sample_len = @min(self.input.len, NodeDensitySampleBytes);
                const lt_count = scanner.countByte(self.input[0..sample_len], '<');
                const projected = std.math.mul(usize, lt_count, self.input.len) catch self.input.len;
                const density_estimate = projected / sample_len;
                break :blk @max(LargeInitialNodeCapacity, density_estimate + density_estimate / 8 + 1);
            };
            self.nodes.ensureTotalCapacity(self.doc.allocator, initial_nodes) catch return error.OutOfMemory;
        }

        fn parse(noalias self: *Self) align(128) ParseError!void {
            try self.initContainers();
            std.debug.assert(self.nodes.items.len == 0);
            _ = self.nodes.addOneAssumeCapacity();
            self.nodes.items[0] = RawNode.initDocument();
            while (self.i + 1 < self.input.len) {
                if (self.input[self.i] != '<') {
                    if (comptime validated) {
                        const text_start = self.i;
                        const whitespace_end = if (tables.WhitespaceTable[self.input[text_start]]) scanner.skipWhitespace(self.input, text_start) else text_start;
                        const has_non_whitespace = whitespace_end == text_start or (whitespace_end < self.input.len and self.input[whitespace_end] != '<');
                        const run = if (has_non_whitespace) scanner.scanTextSpecials(self.input, whitespace_end) else scanner.TextSpecialRun{ .lt_index = whitespace_end };
                        if (run.lt_index > text_start) {
                            try self.validateCharacterDataSpecials(self.input[text_start..run.lt_index], run.has_close_bracket, run.has_ampersand);
                            if (self.current_parent == 0 and has_non_whitespace) return error.InvalidDocumentContent;
                            if (!drop_whitespace_text_nodes or has_non_whitespace) {
                                const parent_idx = self.current_parent;
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
                            const parent_idx = self.current_parent;
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
                        if (self.current_parent == 0 and !tables.WhitespaceTable[self.input[text_start]]) return error.InvalidDocumentContent;
                    }
                    if (!drop_whitespace_text_nodes or !tables.WhitespaceTable[self.input[text_start]]) {
                        _ = try self.appendTextNodeTo(self.current_parent, text_start, self.input.len);
                    }
                }
            }

            if (comptime validated) {
                if (self.current_parent != 0) return error.UnexpectedEndOfData;
                if (!self.validation_flags.root_seen) return error.ExpectedDocumentElement;
            }

            while (self.current_parent != 0) {
                self.closeCurrentNode();
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
                if (name_scan.needs_unicode_validation and !isValidGeneratedXmlName(self.input[name_start..name_end])) return error.ExpectedElementName;
            }
            self.i = name_end;

            const parent_idx = self.current_parent;
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
                    self.current_parent = element_idx;
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
                    self.current_parent = element_idx;
                    return;
                }
            }

            if (comptime validated) {
                if (c0 == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    self.i += 2;
                    _ = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                    try self.maybeConsumeValidatedRepeatedSelfClosing(parent_idx, name_start, name_end);
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
            if (comptime validated) {
                if (!self.validation_flags.simple_tag_disabled and attr_start < self.input.len and self.input[attr_start] == ' ') {
                    if (self.input.len - attr_start >= 7) {
                        const quote_probe = std.mem.readInt(u32, self.input[attr_start + 3 ..][0..4], .little);
                        if (byteMatchMask32(quote_probe, '\'') != 0) {
                            if (scanSimpleValidatedTagAttributes(self.input, attr_start)) |tail| {
                                self.i = tail.end + 1;
                                if (tail.self_closing) {
                                    _ = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                                    try self.maybeConsumeValidatedRepeatedSelfClosing(parent_idx, name_start, name_end);
                                    return;
                                }
                                self.skipDroppedWhitespaceText();
                                const element_idx = try self.appendElementNodeTo(parent_idx, name_start, name_end);
                                if (try self.tryFinishSimpleTextElement(element_idx, name_start, name_end, name_scan.key)) return;
                                self.current_parent = element_idx;
                                return;
                            }
                        }
                    }
                    self.validation_flags.simple_tag_disabled = true;
                } else if (!self.validation_flags.simple_tag_disabled and attr_start < self.input.len and self.input[attr_start] != '>' and self.input[attr_start] != '/') {
                    self.validation_flags.simple_tag_disabled = true;
                }
            }
            if (comptime !validated) {
                const tail_next = scanner.scanStartTagEndFast(self.input, attr_start);
                if (tail_next == 0) {
                    self.i = self.input.len;
                    return error.UnexpectedEndOfData;
                }
                const tail_end = tail_next - 1;
                self.i = tail_next;
                if (tail_end > attr_start and self.input[tail_end - 1] == '/') {
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
                self.current_parent = element_idx;
                return;
            }
            var attribute_names: AttributeNames = .{};
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
                        const duplicate_start = try attribute_names.duplicate(self.doc.allocator, input, attr_start, attr_end);
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
                    self.current_parent = element_idx;
                    return;
                }

                if (c == '/' and self.i + 1 < self.input.len and self.input[self.i + 1] == '>') {
                    const attr_end = self.i;
                    if (comptime validated) {
                        const input = self.input;
                        try self.validateDeferredDtdAttributeReferences(input, attr_start, attr_end);
                        const duplicate_start = try attribute_names.duplicate(self.doc.allocator, input, attr_start, attr_end);
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
                    if (attr_name_needs_unicode_validation and !isValidGeneratedXmlName(self.input[attr_name_start..attr_name_end])) return error.ExpectedAttributeName;
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
                    attribute_names.note(self.input, .{ .start = @intCast(attr_name_start), .end = @intCast(attr_name_end) });
                }
            }

            return error.UnexpectedEndOfData;
        }

        inline fn parseClosingTag(noalias self: *Self) ParseError!void {
            // The open node already supplies a validated name and its length.
            // Match the normal close directly; do not tokenize that name twice.
            const close_start = self.i + 2;
            if (self.current_parent != 0) {
                const name = self.nodes.items[@intCast(self.current_parent)].name_or_text.slice(self.input);
                const remaining = self.input.len - close_start;
                switch (name.len) {
                    1 => if (remaining >= 2) {
                        const pair = std.mem.readInt(u16, self.input[close_start..][0..2], .little);
                        if (pair == @as(u16, name[0]) | (@as(u16, '>') << 8)) {
                            self.i = close_start + 2;
                            self.closeCurrentNode();
                            return;
                        }
                    },
                    2 => if (remaining >= 4) {
                        const word = std.mem.readInt(u32, self.input[close_start..][0..4], .little);
                        const expected = @as(u32, name[0]) | (@as(u32, name[1]) << 8) | (@as(u32, '>') << 16);
                        if (word & 0x00ffffff == expected) {
                            self.i = close_start + 3;
                            self.closeCurrentNode();
                            return;
                        }
                    },
                    3 => if (remaining >= 4) {
                        const word = std.mem.readInt(u32, self.input[close_start..][0..4], .little);
                        const expected = @as(u32, name[0]) | (@as(u32, name[1]) << 8) | (@as(u32, name[2]) << 16) | (@as(u32, '>') << 24);
                        if (word == expected) {
                            self.i = close_start + 4;
                            self.closeCurrentNode();
                            return;
                        }
                    },
                    4 => if (remaining >= 5) {
                        if (std.mem.readInt(u32, self.input[close_start..][0..4], .little) == std.mem.readInt(u32, name[0..4], .little) and self.input[close_start + 4] == '>') {
                            self.i = close_start + 5;
                            self.closeCurrentNode();
                            return;
                        }
                    },
                    5...6 => if (remaining >= 8) {
                        const open_start: usize = @intCast(self.nodes.items[@intCast(self.current_parent)].name_or_text.start);
                        if (self.input.len - open_start >= 8) {
                            const bits: u6 = @intCast(name.len * 8);
                            const name_mask = (@as(u64, 1) << bits) - 1;
                            const compare_bits: u6 = @intCast((name.len + 1) * 8);
                            const compare_mask = (@as(u64, 1) << compare_bits) - 1;
                            const expected = (std.mem.readInt(u64, self.input[open_start..][0..8], .little) & name_mask) | (@as(u64, '>') << bits);
                            if (std.mem.readInt(u64, self.input[close_start..][0..8], .little) & compare_mask == expected) {
                                self.i = close_start + name.len + 1;
                                self.closeCurrentNode();
                                return;
                            }
                        }
                    },
                    7 => if (remaining >= 8) {
                        const open_start: usize = @intCast(self.nodes.items[@intCast(self.current_parent)].name_or_text.start);
                        if (self.input.len - open_start >= 8) {
                            const expected = (std.mem.readInt(u64, self.input[open_start..][0..8], .little) & 0x00ffffffffffffff) | (@as(u64, '>') << 56);
                            if (std.mem.readInt(u64, self.input[close_start..][0..8], .little) == expected) {
                                self.i = close_start + 8;
                                self.closeCurrentNode();
                                return;
                            }
                        }
                    },
                    8 => if (remaining >= 9) {
                        if (std.mem.readInt(u64, self.input[close_start..][0..8], .little) == std.mem.readInt(u64, name[0..8], .little) and self.input[close_start + 8] == '>') {
                            self.i = close_start + 9;
                            self.closeCurrentNode();
                            return;
                        }
                    },
                    else => {},
                }
                if (name.len < remaining) {
                    const close_end = close_start + name.len;
                    if (self.input[close_end] == '>' and
                        std.mem.eql(u8, name, self.input[close_start..close_end]))
                    {
                        self.i = close_end + 1;
                        self.closeCurrentNode();
                        return;
                    }
                }
            }
            return self.parseClosingTagSlow();
        }

        noinline fn parseClosingTagSlow(noalias self: *Self) ParseError!void {
            @branchHint(.cold);
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
                if (close_scan.needs_unicode_validation and !isValidGeneratedXmlName(self.input[close_start..close_end])) {
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

            if (self.current_parent == 0) {
                if (validated) return error.InvalidClosingTagName;
                return;
            }

            const close_name = self.input[close_start..close_end];
            if (self.openNodeMatchesClose(self.current_parent, close_name, close_scan.key)) {
                @branchHint(.likely);
                self.closeCurrentNode();
                return;
            }
            if (validated) return error.InvalidClosingTagName;

            // The node parent chain is already the exact open-element stack.
            // Recover only on mismatch; no duplicate stack or heap spill exists.
            var ancestor = self.nodes.items[@intCast(self.current_parent)].parent;
            while (ancestor != 0) {
                if (self.openNodeMatchesClose(ancestor, close_name, close_scan.key)) {
                    const parent = self.nodes.items[@intCast(ancestor)].parent;
                    while (self.current_parent != parent) self.closeCurrentNode();
                    return;
                }
                ancestor = self.nodes.items[@intCast(ancestor)].parent;
            }
        }

        fn parsePiOrDeclaration(noalias self: *Self) ParseError!void {
            if (comptime validated) {
                if (self.i == 3 and document.utf8BomLen(self.input) == 3) {
                    @branchHint(.unlikely);
                    return self.parsePiOrDeclarationBom();
                }
            }
            return self.parsePiOrDeclarationAt(0);
        }

        noinline fn parsePiOrDeclarationBom(noalias self: *Self) ParseError!void {
            return self.parsePiOrDeclarationAt(3);
        }

        inline fn parsePiOrDeclarationAt(noalias self: *Self, comptime declaration_start: usize) ParseError!void {
            const markup_start = self.i;
            if (comptime validated and !opts.include_misc_nodes) {
                if (markup_start == declaration_start and self.input.len - declaration_start >= 5 and std.mem.eql(u8, self.input[declaration_start..][0..5], "<?xml")) {
                    inline for (.{
                        "<?xml version=\"1.0\"?>",
                        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                        "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\" ?>",
                    }) |canonical| {
                        if (self.input.len - declaration_start >= canonical.len and std.mem.eql(u8, self.input[declaration_start..][0..canonical.len], canonical)) {
                            self.i = declaration_start + canonical.len;
                            self.validation_flags.standalone_yes = false;
                            return;
                        }
                    }
                }
            }
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
                if (target_needs_unicode_validation and !isValidGeneratedXmlName(self.input[target_start..target_end])) return error.ExpectedPiTarget;
            }
            const xml_target = target_end - target_start == 3 and
                std.ascii.eqlIgnoreCase(self.input[target_start..target_end], "xml");
            if (comptime validated) {
                if (xml_target and !std.mem.eql(u8, self.input[target_start..target_end], "xml")) return error.ExpectedPiTarget;
                if (xml_target and markup_start != declaration_start) return error.InvalidDeclaration;
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

            const parent_idx = self.current_parent;
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

                const parent_idx = self.current_parent;
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
                    if (self.current_parent == 0) return error.InvalidDocumentContent;
                }

                const parent_idx = self.current_parent;
                if (comptime opts.include_misc_nodes) {
                    _ = try self.appendMiscNodeTo(
                        parent_idx,
                        .cdata,
                        .{ .start = @intCast(value_start), .end = @intCast(end) },
                        .{},
                    );
                } else if (value_start != end) {
                    _ = try self.appendTextNodeTo(parent_idx, value_start, end);
                }
                return;
            }

            if (scanner.isDoctype(self.input, self.i)) {
                if (comptime validated) {
                    if (!scanner.isDoctypeExact(self.input, self.i)) return error.ExpectedGt;
                    if (self.current_parent != 0 or self.validation_flags.root_seen or self.doctypeSeen()) return error.InvalidDoctype;
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

                const parent_idx = self.current_parent;
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
                const parent = self.nodes.items[@intCast(candidate)].parent;
                if (parent == parent_idx) return candidate;
                if (parent == InvalidIndex or parent >= candidate) return InvalidIndex;
                candidate = parent;
            }
            return InvalidIndex;
        }

        inline fn commitChildMetadata(noalias self: *Self, parent_idx: IndexInt, idx: IndexInt) void {
            if (comptime opts.store_last_child) self.nodes.items[@intCast(parent_idx)].last_child = idx;
        }

        noinline fn growNodes(noalias self: *Self, needed: usize) ParseError!void {
            @branchHint(.cold);
            const len = self.nodes.items.len;
            const target = @max(len + needed, len +| len / 2 +| 8);
            if (self.nodes.capacity == SmallInitialNodeCapacity) {
                var heap = std.ArrayListUnmanaged(RawNode).initCapacity(self.doc.allocator, target) catch return error.OutOfMemory;
                heap.appendSliceAssumeCapacity(self.nodes.items);
                self.nodes = heap;
            } else {
                self.nodes.ensureTotalCapacityPrecise(self.doc.allocator, target) catch return error.OutOfMemory;
            }
        }

        inline fn ensureNodeCapacity(noalias self: *Self, needed: usize) ParseError!void {
            if (self.nodes.capacity - self.nodes.items.len < needed) {
                @branchHint(.unlikely);
                try self.growNodes(needed);
            }
        }

        inline fn maybeConsumeValidatedRepeatedSelfClosing(
            noalias self: *Self,
            parent_idx: IndexInt,
            name_start: usize,
            name_end: usize,
        ) ParseError!void {
            comptime std.debug.assert(validated);
            if (parent_idx == 0 or self.validation_flags.repeat_self_closing == .disabled) return;
            const token_start = name_start - 1;
            const token_len = self.i - token_start;
            if (token_len < 4 or token_len > 128 or self.input.len - self.i < token_len) {
                self.validation_flags.repeat_self_closing = .disabled;
                return;
            }
            const token = self.input[token_start..self.i];
            if (!std.mem.eql(u8, token, self.input[self.i .. self.i + token_len])) {
                self.validation_flags.repeat_self_closing = .disabled;
                return;
            }
            self.validation_flags.repeat_self_closing = .enabled;
            try self.consumeValidatedRepeatedSelfClosingRun(parent_idx, name_start, name_end, token);
        }

        noinline fn consumeValidatedRepeatedSelfClosingRun(
            noalias self: *Self,
            parent_idx: IndexInt,
            name_start: usize,
            name_end: usize,
            token: []const u8,
        ) ParseError!void {
            comptime std.debug.assert(validated);
            const token_len = token.len;
            var cursor = self.i;
            var count: usize = 0;
            while (self.input.len - cursor >= token_len and std.mem.eql(u8, token, self.input[cursor .. cursor + token_len])) {
                count += 1;
                cursor += token_len;
            }
            try self.ensureNodeCapacity(count);
            const name_len = name_end - name_start;
            var repeat_start = self.i;
            for (0..count) |_| {
                const idx: IndexInt = @intCast(self.nodes.items.len);
                const prev = self.previousSiblingForAppend(parent_idx);
                self.nodes.appendAssumeCapacity(RawNode.initElement(
                    idx,
                    parent_idx,
                    .{ .start = @intCast(repeat_start + 1), .end = @intCast(repeat_start + 1 + name_len) },
                    prev,
                ));
                self.commitChildMetadata(parent_idx, idx);
                repeat_start += token_len;
            }
            self.i = cursor;
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

        inline fn closeCurrentNode(noalias self: *Self) void {
            const idx = self.current_parent;
            self.current_parent = self.nodes.items[@intCast(idx)].parent;
            self.finishNode(idx);
        }

        inline fn openNodeMatchesClose(noalias self: *const Self, idx: IndexInt, close_name: []const u8, close_key: u64) bool {
            const open_span = self.nodes.items[@intCast(idx)].name_or_text;
            if (open_span.len() != close_name.len) return false;
            const open_name = open_span.slice(self.input);
            if (scanner.prefixKey(open_name) != close_key) return false;
            return close_name.len <= 8 or std.mem.eql(u8, open_name[8..], close_name[8..]);
        }

        inline fn finishNode(_: *Self, _: IndexInt) void {}

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

    try std.testing.expect(!@hasField(PermissiveParser, "parse_attrs"));
    try std.testing.expect(!@hasField(ValidatedParser, "parse_attrs"));
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
    inline for (.{ "parse_stack", "parse_stack_inline", "parse_stack_heap_owned" }) |field| {
        try std.testing.expect(!@hasField(PermissiveParser, field));
        try std.testing.expect(!@hasField(ValidatedParser, field));
    }
    // Erased fields can fit entirely in alignment padding, notably with u16.
    try std.testing.expect(@sizeOf(PermissiveParser) <= @sizeOf(ValidatedParser));
}

test "permissive generated DOM recovers malformed close structure" {
    const options: ParseOptions = .{};

    var mismatch = "<a><b></a>".*;
    var mismatch_doc = try options.parse(std.testing.allocator, &mismatch);
    defer mismatch_doc.deinit();
    try std.testing.expectEqual(@as(usize, 3), mismatch_doc.nodes.len);

    var unmatched = "<a></x><b/></a>".*;
    var unmatched_doc = try options.parse(std.testing.allocator, &unmatched);
    defer unmatched_doc.deinit();
    try std.testing.expectEqual(@as(usize, 3), unmatched_doc.nodes.len);

    var eof = "<a>".*;
    var eof_doc = try options.parse(std.testing.allocator, &eof);
    defer eof_doc.deinit();
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

test "node parent chain handles deep nesting without an open-element stack" {
    const options: ParseOptions = .{};
    var source: std.ArrayList(u8) = .empty;
    defer source.deinit(std.testing.allocator);
    for (0..80) |_| try source.appendSlice(std.testing.allocator, "<a>");
    try source.appendSlice(std.testing.allocator, "x");
    for (0..80) |_| try source.appendSlice(std.testing.allocator, "</a>");

    var doc = try options.parse(std.testing.allocator, source.items);
    defer doc.deinit();
    try std.testing.expectEqual(@as(usize, 82), doc.nodes.len);
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

test "small node-only documents allocate only their finished nodes" {
    inline for (.{ false, true }) |validated| {
        const options: ParseOptions = .{ .validate_well_formedness = validated };
        var source = "<root id='value' lang='en'><a>text</a><b/></root>".*;
        const Doc = options.Document();
        var storage: [5 * @sizeOf(Doc.RawNode)]u8 align(@alignOf(Doc.RawNode)) = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&storage);
        var doc = try options.parse(fba.allocator(), &source);
        defer doc.deinit();
        try std.testing.expectEqual(@as(usize, 5), doc.nodes.len);
        try std.testing.expectEqualStrings("value", doc.nodeAt(1).?.getAttributeValueRaw("id").?);
    }
}

test "inline node storage spills safely and releases every failed allocation" {
    const Check = struct {
        fn run(allocator: std.mem.Allocator) !void {
            const options: ParseOptions = .{ .validate_well_formedness = true };
            var source = ("<r>" ++ "<a>value</a>" ** 90 ++ "</r>").*;
            var doc = try options.parse(allocator, &source);
            defer doc.deinit();
            try std.testing.expectEqual(@as(usize, 182), doc.nodes.len);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Check.run, .{});
}

test "node-only parsing rejects quoted raw greater-than instead of corrupting the tree" {
    var source = "<r a='left>right'/>".*;
    const fast: ParseOptions = .{};
    try std.testing.expectError(error.UnexpectedEndOfData, fast.parse(std.testing.allocator, &source));
    const full: ParseOptions = .{ .validate_well_formedness = true };
    var doc = try full.parse(std.testing.allocator, &source);
    defer doc.deinit();
    try std.testing.expectEqualStrings("left>right", doc.nodeAt(1).?.getAttributeValueRaw("a").?);
}

test "direct closing match preserves whitespace mismatch and partial tails" {
    const options: ParseOptions = .{ .validate_well_formedness = true };
    inline for (.{ "<r><n></n></r>", "<r><abcdefghX></abcdefghX></r>", "<r><n></n \t\r\n></r>" }) |text| {
        var input = text.*;
        var doc = try options.parse(std.testing.allocator, &input);
        defer doc.deinit();
        try std.testing.expectEqual(@as(usize, 3), doc.nodes.len);
    }
    inline for (.{ "<r><abcdefghX></abcdefghY></r>", "<r><n></nX></r>" }) |text| {
        var input = text.*;
        try std.testing.expectError(error.InvalidClosingTagName, options.parse(std.testing.allocator, &input));
    }
    inline for (.{ "<r></", "<r></r", "<r><abcdefghX></abcdefgh" }) |text| {
        var input = text.*;
        try std.testing.expectError(error.UnexpectedEndOfData, options.parse(std.testing.allocator, &input));
    }
}

test "parseDiagnostic reports XML character error location" {
    const options: ParseOptions = .{ .validate_well_formedness = true };
    var source = "<r>abc\x01def</r>".*;
    const diagnostic = options.parseDiagnostic(std.testing.allocator, &source) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(error.InvalidXmlCharacter, diagnostic.err);
    try std.testing.expectEqual(@as(usize, 6), diagnostic.offset);
    try std.testing.expectEqual(@as(usize, 1), diagnostic.location().line);
    try std.testing.expectEqual(@as(usize, 7), diagnostic.location().column);
}

test "validated DOM accepts a leading UTF-8 BOM" {
    inline for (.{ false, true }) |immutable| {
        var source = "\xEF\xBB\xBF<?xml version='1.0'?><r>text</r>".*;
        const options: ParseOptions = .{ .validate_well_formedness = true, .non_destructive = immutable };
        const input = if (immutable) @as([]const u8, &source) else @as([]u8, &source);
        var doc = try options.parse(std.testing.allocator, input);
        defer doc.deinit();
        try std.testing.expectEqualStrings("r", doc.nodeAt(1).?.nameSlice());
        try std.testing.expectEqualStrings("text", doc.nodeAt(1).?.firstChild().?.valueRawSlice());
    }
}
