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
    first_child: u32 = InvalidIndex,
    last_child: u32 = InvalidIndex,
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
    kind: NodeType,

    name: Span = .{},
    value: Span = .{},

    attr_start: u32 = 0,
    attr_len: u32 = 0,

    first_child: u32 = InvalidIndex,
    last_child: u32 = InvalidIndex,
    next_sibling: u32 = InvalidIndex,
    parent: u32 = InvalidIndex,

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
        const self_index = self.indexOfSelf();

        if (self.parent != InvalidIndex) {
            const p = self.doc.nodeAt(self.parent) orelse return null;
            var prev = InvalidIndex;
            var cur = p.first_child;
            while (cur != InvalidIndex and cur != self_index) {
                prev = cur;
                cur = self.doc.nodes.items[cur].next_sibling;
            }
            return self.doc.nodeAt(prev);
        }

        // Fallback when parent pointers are disabled: scan next-sibling links.
        var i: u32 = 0;
        while (i < self.doc.nodes.items.len) : (i += 1) {
            if (self.doc.nodes.items[i].next_sibling == self_index) return &self.doc.nodes.items[i];
        }
        return null;
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

    fn indexOfSelf(self: *const @This()) u32 {
        const base = @intFromPtr(self.doc.nodes.items.ptr);
        const here = @intFromPtr(self);
        const stride = @sizeOf(@This());
        return @intCast((here - base) / stride);
    }
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    source: []u8 = &[_]u8{},
    reserved_input_hint_len: usize = 0,

    nodes: std.ArrayListUnmanaged(Node) = .{},
    attrs: std.ArrayListUnmanaged(Attribute) = .{},
    parse_stack: std.ArrayListUnmanaged(ParseStackEntry) = .{},

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
        self.nodes.items.len = 0;
        self.attrs.items.len = 0;
        self.parse_stack.items.len = 0;
    }

    pub fn parse(noalias self: *Document, noalias input: []u8, comptime opts: ParseOptions) ParseError!void {
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

    pub fn appendNode(noalias self: *Document, kind: NodeType, parent_idx: u32, comptime store_parent: bool) !u32 {
        if (self.nodes.items.len == self.nodes.capacity) {
            try self.nodes.ensureUnusedCapacity(self.allocator, 1);
        }
        const idx: u32 = @intCast(self.nodes.items.len);
        const node = Node{
            .doc = self,
            .kind = kind,
            .parent = if (store_parent) parent_idx else InvalidIndex,
        };

        const out = self.nodes.addOneAssumeCapacity();
        out.* = node;
        return idx;
    }

    pub fn appendAttribute(noalias self: *Document, name: Span, value: Span) !u32 {
        if (self.attrs.items.len == self.attrs.capacity) {
            try self.attrs.ensureUnusedCapacity(self.allocator, 1);
        }
        const idx: u32 = @intCast(self.attrs.items.len);
        const out = self.attrs.addOneAssumeCapacity();
        out.* = .{
            .doc = self,
            .name = name,
            .value = value,
        };

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
};
