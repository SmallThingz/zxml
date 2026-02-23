const std = @import("std");
const parser = @import("parser.zig");

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
    // Turbo throughput mode that skips DOM construction and input scanning.
    scan_only_turbo: bool = false,
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

pub const Attribute = struct {
    doc: *Document,
    owner_index: u32,
    index: u32,
    name: Span,
    value: Span,

    pub fn nameSlice(self: *const @This()) []const u8 {
        return self.name.slice(self.doc.source);
    }

    pub fn valueSlice(self: *const @This()) []const u8 {
        return self.value.slice(self.doc.source);
    }
};

pub const Node = struct {
    doc: *Document,
    index: u32,
    kind: NodeType,

    name: Span = .{},
    value: Span = .{},

    open_start: u32 = 0,
    open_end: u32 = 0,
    close_start: u32 = 0,
    close_end: u32 = 0,

    attr_start: u32 = 0,
    attr_len: u32 = 0,

    first_child: u32 = InvalidIndex,
    last_child: u32 = InvalidIndex,
    prev_sibling: u32 = InvalidIndex,
    next_sibling: u32 = InvalidIndex,
    parent: u32 = InvalidIndex,

    subtree_end: u32 = 0,

    pub fn nameSlice(self: *const @This()) []const u8 {
        return self.name.slice(self.doc.source);
    }

    pub fn valueSlice(self: *const @This()) []const u8 {
        return self.value.slice(self.doc.source);
    }

    pub fn firstChild(self: *const @This()) ?*const @This() {
        return self.doc.nodeAt(self.first_child);
    }

    pub fn lastChild(self: *const @This()) ?*const @This() {
        return self.doc.nodeAt(self.last_child);
    }

    pub fn nextSibling(self: *const @This()) ?*const @This() {
        return self.doc.nodeAt(self.next_sibling);
    }

    pub fn prevSibling(self: *const @This()) ?*const @This() {
        return self.doc.nodeAt(self.prev_sibling);
    }

    pub fn parentNode(self: *const @This()) ?*const @This() {
        return self.doc.nodeAt(self.parent);
    }

    pub fn getAttributeValue(self: *const @This(), name: []const u8) ?[]const u8 {
        var i = self.attr_start;
        const end = self.attr_start + self.attr_len;
        while (i < end) : (i += 1) {
            const attr = &self.doc.attrs.items[i];
            if (std.mem.eql(u8, attr.name.slice(self.doc.source), name)) {
                return attr.value.slice(self.doc.source);
            }
        }
        return null;
    }

    pub fn firstAttribute(self: *const @This()) ?*const Attribute {
        if (self.attr_len == 0) return null;
        return &self.doc.attrs.items[self.attr_start];
    }
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    source: []u8 = &[_]u8{},

    nodes: std.ArrayListUnmanaged(Node) = .{},
    attrs: std.ArrayListUnmanaged(Attribute) = .{},
    parse_stack: std.ArrayListUnmanaged(u32) = .{},

    pub fn init(allocator: std.mem.Allocator) Document {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Document) void {
        self.nodes.deinit(self.allocator);
        self.attrs.deinit(self.allocator);
        self.parse_stack.deinit(self.allocator);
    }

    pub fn clear(self: *Document) void {
        self.nodes.clearRetainingCapacity();
        self.attrs.clearRetainingCapacity();
        self.parse_stack.clearRetainingCapacity();
    }

    pub fn parse(self: *Document, input: []u8, comptime opts: ParseOptions) ParseError!void {
        self.clear();
        self.source = input;
        try parser.parseInto(self, input, opts);
    }

    pub fn root(self: *const Document) ?*const Node {
        if (self.nodes.items.len == 0) return null;
        return &self.nodes.items[0];
    }

    pub fn rootMut(self: *Document) ?*Node {
        if (self.nodes.items.len == 0) return null;
        return &self.nodes.items[0];
    }

    pub fn nodeAt(self: *const Document, idx: u32) ?*const Node {
        if (idx == InvalidIndex or idx >= self.nodes.items.len) return null;
        return &self.nodes.items[idx];
    }

    pub fn nodeAtMut(self: *Document, idx: u32) ?*Node {
        if (idx == InvalidIndex or idx >= self.nodes.items.len) return null;
        return &self.nodes.items[idx];
    }

    pub fn appendNode(self: *Document, kind: NodeType, parent_idx: u32, store_parent: bool) !u32 {
        const idx: u32 = @intCast(self.nodes.items.len);
        var node = Node{
            .doc = self,
            .index = idx,
            .kind = kind,
            .parent = if (store_parent) parent_idx else InvalidIndex,
            .subtree_end = idx,
        };

        if (parent_idx != InvalidIndex) {
            const parent = &self.nodes.items[parent_idx];
            if (parent.last_child == InvalidIndex) {
                node.prev_sibling = InvalidIndex;
                parent.first_child = idx;
                parent.last_child = idx;
            } else {
                node.prev_sibling = parent.last_child;
                self.nodes.items[parent.last_child].next_sibling = idx;
                parent.last_child = idx;
            }
        }

        try self.nodes.append(self.allocator, node);
        return idx;
    }

    pub fn appendAttribute(self: *Document, owner_idx: u32, name: Span, value: Span) !u32 {
        const idx: u32 = @intCast(self.attrs.items.len);
        try self.attrs.append(self.allocator, .{
            .doc = self,
            .owner_index = owner_idx,
            .index = idx,
            .name = name,
            .value = value,
        });

        var owner = &self.nodes.items[owner_idx];
        if (owner.attr_len == 0) owner.attr_start = idx;
        owner.attr_len += 1;

        return idx;
    }

    pub fn reserveForInput(self: *Document, input_len: usize) !void {
        const est_nodes = @max(@as(usize, 16), input_len / 14 + 8);
        const est_attrs = @max(@as(usize, 16), input_len / 32 + 8);
        const est_stack = @max(@as(usize, 8), input_len / 512 + 8);

        try self.nodes.ensureTotalCapacity(self.allocator, est_nodes);
        try self.attrs.ensureTotalCapacity(self.allocator, est_attrs);
        try self.parse_stack.ensureTotalCapacity(self.allocator, est_stack);
    }
};
