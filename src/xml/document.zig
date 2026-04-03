const std = @import("std");
const parser = @import("parser.zig");
const entities = @import("entities.zig");

pub const InvalidIndex: u32 = std.math.maxInt(u32);

pub const ParseMode = enum {
    turbo,
    strict,
};

pub const ParseOptions = struct {
    mode: ParseMode = .turbo,
    validate_closing_tags: bool = false,
    decode_entities_on_parse: bool = false,
    normalize_text_whitespace: bool = false,
    store_parent_pointers: bool = false,
    include_misc_nodes: bool = true,
};

pub const ParseError = error{
    OutOfMemory,
    UnexpectedEndOfData,
    ExpectedLt,
    ExpectedGt,
    ExpectedElementName,
    ExpectedAttributeName,
    ExpectedEq,
    ExpectedQuote,
    ExpectedPiTarget,
    InvalidClosingTagName,
    InvalidNumericCharacterEntity,
    UnterminatedEntity,
};

pub const ParseStackEntry = struct {
    idx: u32,
    tag_key: u64 = 0,
    tag_len: u16 = 0,
};

pub const NodeType = enum(u4) {
    document,
    element,
    text,
    comment,
    cdata,
    pi,
    declaration,
    doctype,
};

pub const Span = struct {
    start: u32 = 0,
    end: u32 = 0,

    pub fn len(self: @This()) u32 {
        return self.end - self.start;
    }

    pub fn isEmpty(self: @This()) bool {
        return self.start == self.end;
    }

    pub fn slice(self: @This(), source: []const u8) []const u8 {
        return source[self.start..self.end];
    }

    pub fn sliceMut(self: @This(), source: []u8) []u8 {
        return source[self.start..self.end];
    }
};

pub const RawAttribute = struct {
    name: Span,
    value: Span,
    value_processed: bool = true,
};

pub const Attribute = struct {
    doc: *Document,
    index: u32,

    inline fn raw(self: @This()) *RawAttribute {
        return &self.doc.attrs.items[self.index];
    }

    pub fn nameSlice(self: @This()) []const u8 {
        return self.raw().name.slice(self.doc.source);
    }

    pub fn valueSlice(self: @This()) []const u8 {
        self.doc.ensureAttributeValueProcessed(self.index);
        return self.raw().value.slice(self.doc.source);
    }
};

pub const RawNode = struct {
    kind: NodeType,

    name: Span = .{},
    value: Span = .{},
    value_processed: bool = true,

    attr_start: u32 = 0,
    attr_len: u32 = 0,

    last_child: u32 = InvalidIndex,
    prev_sibling: u32 = InvalidIndex,
    subtree_end: u32 = 0,
};

pub const Node = struct {
    doc: *Document,
    index: u32,
    kind: NodeType,
    attr_start: u32 = 0,
    attr_len: u32 = 0,

    inline fn raw(self: @This()) *RawNode {
        return &self.doc.nodes.items[self.index];
    }

    pub fn nameSlice(self: @This()) []const u8 {
        return self.raw().name.slice(self.doc.source);
    }

    pub fn valueSlice(self: @This()) []const u8 {
        self.doc.ensureNodeValueProcessed(self.index);
        return self.raw().value.slice(self.doc.source);
    }

    pub fn firstChild(self: @This()) ?Node {
        const node_raw = self.raw();
        if (node_raw.subtree_end <= self.index) return null;
        return self.doc.nodeAt(self.index + 1);
    }

    pub fn lastChild(self: @This()) ?Node {
        return self.doc.nodeAt(self.raw().last_child);
    }

    pub fn nextSibling(self: @This()) ?Node {
        const next_idx = self.raw().subtree_end + 1;
        if (next_idx >= self.doc.nodes.items.len) return null;
        if (self.doc.nodes.items[next_idx].prev_sibling != self.index) return null;
        return self.doc.nodeAt(next_idx);
    }

    pub fn prevSibling(self: @This()) ?Node {
        return self.doc.nodeAt(self.raw().prev_sibling);
    }

    pub fn parentNode(self: @This()) ?Node {
        const parent_idx = self.doc.parentIndex(self.index) orelse return null;
        return self.doc.nodeAt(parent_idx);
    }

    pub fn getAttributeValue(self: @This(), name: []const u8) ?[]const u8 {
        const node_raw = self.raw();
        var i = node_raw.attr_start;
        const end = node_raw.attr_start + node_raw.attr_len;
        while (i < end) : (i += 1) {
            if (std.mem.eql(u8, self.doc.attrs.items[i].name.slice(self.doc.source), name)) {
                const attr: Attribute = .{ .doc = self.doc, .index = i };
                return attr.valueSlice();
            }
        }
        return null;
    }

    pub fn firstAttribute(self: @This()) ?Attribute {
        const node_raw = self.raw();
        if (node_raw.attr_len == 0) return null;
        return .{ .doc = self.doc, .index = node_raw.attr_start };
    }
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    source: []u8 = &[_]u8{},
    reserved_input_hint_len: usize = 0,
    postprocess_decode_entities: bool = false,
    postprocess_normalize_text: bool = false,

    nodes: std.ArrayList(RawNode) = .empty,
    attrs: std.ArrayList(RawAttribute) = .empty,
    parse_stack: std.ArrayList(ParseStackEntry) = .empty,
    parents: std.ArrayList(u32) = .empty,

    pub fn init(allocator: std.mem.Allocator) Document {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Document) void {
        self.nodes.deinit(self.allocator);
        self.attrs.deinit(self.allocator);
        self.parse_stack.deinit(self.allocator);
        self.parents.deinit(self.allocator);
    }

    pub fn clear(self: *Document) void {
        self.nodes.items.len = 0;
        self.attrs.items.len = 0;
        self.parse_stack.items.len = 0;
        self.parents.items.len = 0;
    }

    pub fn parse(noalias self: *Document, noalias input: []u8, comptime opts: ParseOptions) ParseError!void {
        self.clear();
        self.source = input;
        self.postprocess_decode_entities = opts.decode_entities_on_parse;
        self.postprocess_normalize_text = opts.normalize_text_whitespace;
        if (comptime opts.store_parent_pointers) {
            try self.reserveParentsForInput(input.len);
        }
        try parser.parseInto(self, input, opts);
    }

    pub fn root(self: *const Document) ?Node {
        return @constCast(self).nodeAt(0);
    }

    pub fn rootMut(self: *Document) ?Node {
        return self.nodeAt(0);
    }

    pub fn nodeAt(self: *const Document, idx: u32) ?Node {
        if (idx == InvalidIndex or idx >= self.nodes.items.len) return null;
        const doc = @constCast(self);
        return .{
            .doc = doc,
            .index = idx,
            .kind = doc.nodes.items[idx].kind,
            .attr_start = doc.nodes.items[idx].attr_start,
            .attr_len = doc.nodes.items[idx].attr_len,
        };
    }

    pub fn nodeAtMut(self: *Document, idx: u32) ?Node {
        return self.nodeAt(idx);
    }

    pub fn appendNode(noalias self: *Document, kind: NodeType, parent_idx: u32, comptime store_parent: bool) !u32 {
        if (self.nodes.items.len == self.nodes.capacity) {
            try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        }
        if (comptime store_parent) {
            if (self.parents.items.len == self.parents.capacity) {
                try self.parents.ensureUnusedCapacity(self.allocator, 1);
            }
        }
        const idx: u32 = @intCast(self.nodes.items.len);
        const node = RawNode{ .kind = kind, .subtree_end = idx };

        const out = self.nodes.addOneAssumeCapacity();
        out.* = node;
        if (comptime store_parent) {
            const parent_out = self.parents.addOneAssumeCapacity();
            parent_out.* = parent_idx;
        }
        return idx;
    }

    pub fn appendAttribute(noalias self: *Document, name: Span, value: Span) !u32 {
        if (self.attrs.items.len == self.attrs.capacity) {
            try self.attrs.ensureUnusedCapacity(self.allocator, 1);
        }
        const idx: u32 = @intCast(self.attrs.items.len);
        const out = self.attrs.addOneAssumeCapacity();
        out.* = .{ .name = name, .value = value };

        return idx;
    }

    pub fn reserveForInput(self: *Document, input_len: usize) !void {
        if (input_len <= self.reserved_input_hint_len and
            self.nodes.capacity > 0 and
            self.attrs.capacity > 0 and
            self.parse_stack.capacity > 0)
        {
            return;
        }

        const est_nodes = @max(@as(usize, 16), input_len / 14 + 8);
        const est_attrs = @max(@as(usize, 16), input_len / 32 + 8);
        const est_stack = @max(@as(usize, 8), input_len / 512 + 8);

        if (est_nodes > self.nodes.capacity) {
            try self.nodes.ensureTotalCapacity(self.allocator, est_nodes);
        }
        if (est_attrs > self.attrs.capacity) {
            try self.attrs.ensureTotalCapacity(self.allocator, est_attrs);
        }
        if (est_stack > self.parse_stack.capacity) {
            try self.parse_stack.ensureTotalCapacity(self.allocator, est_stack);
        }
        self.reserved_input_hint_len = input_len;
    }

    pub fn reserveParentsForInput(self: *Document, input_len: usize) !void {
        const est_nodes = @max(@as(usize, 16), input_len / 14 + 8);
        if (est_nodes > self.parents.capacity) {
            try self.parents.ensureTotalCapacity(self.allocator, est_nodes);
        }
    }

    fn parentIndex(self: *const Document, idx: u32) ?u32 {
        if (idx == InvalidIndex or idx == 0 or idx >= self.nodes.items.len) return null;
        if (idx < self.parents.items.len) {
            const parent = self.parents.items[idx];
            if (parent != InvalidIndex) return parent;
        }
        return null;
    }

    fn ensureNodeValueProcessed(self: *Document, idx: u32) void {
        var node = &self.nodes.items[idx];
        if (node.value_processed) return;
        if (node.kind != .text) {
            node.value_processed = true;
            return;
        }
        if (!self.postprocess_decode_entities and !self.postprocess_normalize_text) {
            node.value_processed = true;
            return;
        }

        const value = node.value.sliceMut(self.source);
        var final_len = value.len;
        if (self.postprocess_decode_entities and self.postprocess_normalize_text) {
            final_len = entities.decodeAndNormalizeInPlace(value, false) catch value.len;
        } else if (self.postprocess_decode_entities) {
            final_len = entities.decodeInPlaceIfEntity(value, false) catch value.len;
        } else if (self.postprocess_normalize_text) {
            final_len = entities.normalizeWhitespaceInPlace(value);
        }

        node.value.end = node.value.start + @as(u32, @intCast(final_len));
        node.value_processed = true;
    }

    fn ensureAttributeValueProcessed(self: *Document, idx: u32) void {
        var attr = &self.attrs.items[idx];
        if (attr.value_processed) return;
        if (!self.postprocess_decode_entities) {
            attr.value_processed = true;
            return;
        }

        const value = attr.value.sliceMut(self.source);
        const final_len = entities.decodeInPlaceIfEntity(value, false) catch value.len;
        attr.value.end = attr.value.start + @as(u32, @intCast(final_len));
        attr.value_processed = true;
    }
};
