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
    require_closed_elements_on_eof: bool = false,
    decode_entities_on_parse: bool = false,
    drop_whitespace_text_nodes: bool = true,
    include_misc_nodes: bool = true,
};

pub fn Types(comptime options: ParseOptions) type {
    _ = options;
    return struct {
        pub const Span = @import("document.zig").Span;
        pub const RawAttribute = @import("document.zig").RawAttribute;
        pub const Attribute = @import("document.zig").Attribute;
        pub const RawNode = @import("document.zig").RawNode;
        pub const Node = @import("document.zig").Node;
        pub const Document = @import("document.zig").Document;
    };
}

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
        var attr = self.raw();
        if (!attr.value_processed) {
            if (self.doc.postprocess_decode_entities) {
                const value = attr.value.sliceMut(self.doc.source);
                const final_len = entities.decodeInPlaceIfEntity(value, false) catch value.len;
                attr.value.end = attr.value.start + @as(u32, @intCast(final_len));
            }
            attr.value_processed = true;
        }
        return attr.value.slice(self.doc.source);
    }
};

pub const RawNode = struct {
    kind: NodeType,

    name: Span = .{},
    value: Span = .{},
    value_processed: bool = true,

    attr_start: u32 = 0,
    attr_len: u32 = 0,

    parent: u32 = InvalidIndex,
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
        var node = self.raw();
        if (!node.value_processed) {
            if (node.kind == .text and self.doc.postprocess_decode_entities) {
                const value = node.value.sliceMut(self.doc.source);
                const final_len = entities.decodeInPlaceIfEntity(value, false) catch value.len;
                node.value.end = node.value.start + @as(u32, @intCast(final_len));
            }
            node.value_processed = true;
        }
        return node.value.slice(self.doc.source);
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
        return self.doc.nodeAt(self.raw().parent);
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

    nodes: std.ArrayList(RawNode) = .empty,
    attrs: std.ArrayList(RawAttribute) = .empty,
    parse_stack: std.ArrayList(ParseStackEntry) = .empty,

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
        self.postprocess_decode_entities = opts.decode_entities_on_parse;
        try parser.parseInto(self, input, opts);
    }

    pub fn root(self: *const Document) ?Node {
        return @constCast(self).nodeAt(0);
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

    pub fn reserveForInput(self: *Document, input_len: usize) !void {
        if (input_len <= self.reserved_input_hint_len) {
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

test "Types(options) exposes concrete DOM types" {
    const opts: ParseOptions = .{};
    const types = Types(opts);
    try std.testing.expectEqual(Span, types.Span);
    try std.testing.expectEqual(RawNode, types.RawNode);
    try std.testing.expectEqual(Node, types.Node);
    try std.testing.expectEqual(RawAttribute, types.RawAttribute);
    try std.testing.expectEqual(Attribute, types.Attribute);
    try std.testing.expectEqual(Document, types.Document);
}

test "Span helpers expose slices and lengths" {
    const opts: ParseOptions = .{};
    const SpanType = Types(opts).Span;
    var buf = "abcdef".*;
    const span: SpanType = .{ .start = 1, .end = 4 };
    try std.testing.expectEqual(@as(u32, 3), span.len());
    try std.testing.expect(!span.isEmpty());
    try std.testing.expectEqualStrings("bcd", span.slice(&buf));

    const mut = span.sliceMut(&buf);
    mut[1] = 'Z';
    try std.testing.expectEqualStrings("bZd", span.slice(&buf));

    const empty: SpanType = .{ .start = 2, .end = 2 };
    try std.testing.expect(empty.isEmpty());
}

test "Document reserve and lookup helpers behave on empty and populated state" {
    const opts: ParseOptions = .{};
    const DocumentType = Types(opts).Document;
    var doc = DocumentType.init(std.testing.allocator);
    defer doc.deinit();

    try std.testing.expect(doc.root() == null);
    try std.testing.expect(doc.nodeAt(InvalidIndex) == null);
    try std.testing.expect(doc.nodeAt(0) == null);

    try doc.reserveForInput(256);
    try std.testing.expect(doc.nodes.capacity >= 16);
    try std.testing.expect(doc.attrs.capacity >= 16);
    try std.testing.expect(doc.parse_stack.capacity >= 8);

    var xml = "<r a='&amp;'>&lt;x&gt;</r>".*;
    try doc.parse(&xml, .{ .mode = .strict, .decode_entities_on_parse = true });
    try std.testing.expect(doc.root() != null);
    try std.testing.expect(doc.nodeAt(1) != null);

    const root = doc.nodeAt(1).?;
    try std.testing.expectEqualStrings("&", root.getAttributeValue("a").?);
    try std.testing.expectEqualStrings("<x>", root.firstChild().?.valueSlice());
    try std.testing.expectEqual(@as(u32, 0), root.parentNode().?.index);
    try std.testing.expectEqual(root.index, root.firstChild().?.parentNode().?.index);

    doc.clear();
    try std.testing.expect(doc.root() == null);
    try std.testing.expectEqual(@as(usize, 0), doc.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 0), doc.attrs.items.len);
}
