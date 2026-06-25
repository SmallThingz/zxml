const std = @import("std");
const common = @import("common.zig");
const parser = @import("parser.zig");
const entities = @import("entities.zig");
const tables = @import("tables.zig");

pub const IndexInt = common.IndexInt;
pub const InvalidIndex: IndexInt = common.InvalidIndex;

pub const ParseMode = enum {
    turbo,
    strict,
};

pub const ParseOptions = struct {
    mode: ParseMode = .turbo,
    validate_closing_tags: bool = false,
    require_closed_elements_on_eof: bool = false,
    expand_dtd_entities: bool = false,
    max_entity_value_len: usize = 4096,
    drop_whitespace_text_nodes: bool = true,
    include_misc_nodes: bool = true,

    /// Returns the accepted parse input slice type for this option set.
    /// zxml never mutates caller bytes, so this is always `[]const u8`.
    pub fn Input(_: @This()) type {
        return []const u8;
    }

    /// Parses `input` and returns an owned document for this option set.
    pub fn parse(comptime options: @This(), allocator: std.mem.Allocator, input: options.Input()) ParseError!options.Document() {
        var doc = options.Document().init(allocator);
        errdefer doc.deinit();
        try doc.parse(input, options);
        return doc;
    }

    /// Parses `input`; returns null on success or a lazy diagnostic on failure.
    pub fn parseDiagnostic(comptime options: @This(), allocator: std.mem.Allocator, input: options.Input()) !ParseDiagnosticResult(options.Document()) {
        var doc = options.Document().init(allocator);
        errdefer doc.deinit();
        if (doc.parseDiagnostic(input, options)) |diag| {
            doc.deinit();
            return .{ .diagnostic = diag };
        }
        return .{ .document = doc };
    }

    /// Returns the document type for this option set.
    pub fn Document(comptime options: @This()) type {
        return Types(options).Document;
    }

    /// Returns the node wrapper type for this option set.
    pub fn Node(comptime options: @This()) type {
        return Types(options).Node;
    }

    /// Returns the attribute wrapper type for this option set.
    pub fn Attribute(comptime options: @This()) type {
        return Types(options).Attribute;
    }

    /// Returns raw node storage for this option set.
    pub fn RawNode(comptime options: @This()) type {
        return Types(options).RawNode;
    }

    /// Returns raw attribute storage for this option set.
    pub fn RawAttribute(comptime options: @This()) type {
        return Types(options).RawAttribute;
    }
};

pub fn Types(comptime options: ParseOptions) type {
    _ = options;
    return struct {
        pub const IndexInt = @import("document.zig").IndexInt;
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
    InputTooLarge,
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
    EntityValueTooLarge,
};

pub const ParseDiagnostic = struct {
    err: ParseError,
    offset: usize,
    source: []const u8,

    pub const Location = struct {
        line: usize,
        column: usize,
    };

    pub fn location(self: @This()) Location {
        var line: usize = 1;
        var column: usize = 1;
        var i: usize = 0;
        const end = @min(self.offset, self.source.len);
        while (i < end) : (i += 1) {
            if (self.source[i] == '\n') {
                line += 1;
                column = 1;
            } else {
                column += 1;
            }
        }
        return .{ .line = line, .column = column };
    }

    pub fn context(self: @This(), radius: usize) []const u8 {
        const center = @min(self.offset, self.source.len);
        const start = center - @min(center, radius);
        const end = @min(self.source.len, center + radius);
        return self.source[start..end];
    }
};

pub fn ParseDiagnosticResult(comptime DocumentType: type) type {
    return union(enum) {
        document: DocumentType,
        diagnostic: ParseDiagnostic,
    };
}

pub const ParseStackEntry = struct {
    idx: IndexInt,
    /// Low-cost fingerprint of the first up-to-8 bytes of the open tag name.
    tag_key: u64 = 0,
    /// Full tag-name length so close-tag validation can reject mismatches
    /// before touching the source bytes again.
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
    start: IndexInt = 0,
    end: IndexInt = 0,

    pub fn len(self: @This()) IndexInt {
        return self.end - self.start;
    }

    pub fn isEmpty(self: @This()) bool {
        return self.start == self.end;
    }

    pub fn slice(self: @This(), source: []const u8) []const u8 {
        return source[self.start..self.end];
    }
};

pub const RawAttribute = struct {
    name: Span,
    value: Span,
};

pub const RawNode = struct {
    kind: NodeType,

    name: Span = .{},
    value: Span = .{},

    attr_start: IndexInt = 0,
    attr_len: IndexInt = 0,

    parent: IndexInt = InvalidIndex,
    /// Index of the last direct child, which makes append and reverse-sibling
    /// traversal O(1) without a separate sibling list allocation.
    last_child: IndexInt = InvalidIndex,
    /// Previous direct sibling in document order. `nextSibling()` is derived
    /// from `subtree_end + 1`.
    prev_sibling: IndexInt = InvalidIndex,
    /// Inclusive end index of this node's flattened subtree in `nodes.items`.
    subtree_end: IndexInt = 0,
};

const ValueError = std.mem.Allocator.Error || entities.DecodeError;

pub const Attribute = struct {
    doc: *Document,
    index: IndexInt,

    inline fn raw(self: @This()) *const RawAttribute {
        return &self.doc.attrs.items[self.index];
    }

    pub fn nameSlice(self: @This()) []const u8 {
        return self.raw().name.slice(self.doc.source);
    }

    pub fn valueRawSlice(self: @This()) []const u8 {
        return self.raw().value.slice(self.doc.source);
    }

    pub fn namespacePrefix(self: @This()) ?[]const u8 {
        const name = self.nameSlice();
        const split = std.mem.indexOfScalar(u8, name, ':') orelse return null;
        return name[0..split];
    }

    pub fn localName(self: @This()) []const u8 {
        const name = self.nameSlice();
        const split = std.mem.indexOfScalar(u8, name, ':') orelse return name;
        return name[split + 1 ..];
    }

    pub fn value(self: @This(), alloc: std.mem.Allocator) ValueError![]u8 {
        return self.doc.decodeValueAlloc(alloc, self.valueRawSlice());
    }
};

pub const Node = struct {
    doc: *Document,
    index: IndexInt,
    kind: NodeType,
    attr_start: IndexInt = 0,
    attr_len: IndexInt = 0,

    inline fn raw(self: @This()) *const RawNode {
        return &self.doc.nodes.items[self.index];
    }

    inline fn findAttributeIndex(self: @This(), name: []const u8) ?IndexInt {
        const node_raw = self.raw();
        var i = node_raw.attr_start;
        const end = node_raw.attr_start + node_raw.attr_len;
        while (i < end) : (i += 1) {
            if (std.mem.eql(u8, self.doc.attrs.items[i].name.slice(self.doc.source), name)) {
                return i;
            }
        }
        return null;
    }

    pub fn nameSlice(self: @This()) []const u8 {
        return self.raw().name.slice(self.doc.source);
    }

    pub fn namespacePrefix(self: @This()) ?[]const u8 {
        const name = self.nameSlice();
        const split = std.mem.indexOfScalar(u8, name, ':') orelse return null;
        return name[0..split];
    }

    pub fn localName(self: @This()) []const u8 {
        const name = self.nameSlice();
        const split = std.mem.indexOfScalar(u8, name, ':') orelse return name;
        return name[split + 1 ..];
    }

    pub fn namespaceUri(self: @This()) ?[]const u8 {
        const prefix = self.namespacePrefix();
        var cur: ?Node = self;
        while (cur) |node| : (cur = node.parentNode()) {
            const node_raw = node.raw();
            var i = node_raw.attr_start;
            const end = node_raw.attr_start + node_raw.attr_len;
            while (i < end) : (i += 1) {
                const attr = node.doc.attrs.items[i];
                const name = attr.name.slice(node.doc.source);
                if (prefix) |p| {
                    if (std.mem.startsWith(u8, name, "xmlns:") and std.mem.eql(u8, name["xmlns:".len..], p)) return attr.value.slice(node.doc.source);
                } else if (std.mem.eql(u8, name, "xmlns")) return attr.value.slice(node.doc.source);
            }
        }
        return null;
    }

    pub fn valueRawSlice(self: @This()) []const u8 {
        return self.raw().value.slice(self.doc.source);
    }

    pub fn value(self: @This(), alloc: std.mem.Allocator) ValueError![]u8 {
        return self.doc.decodeValueAlloc(alloc, self.valueRawSlice());
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
        if (@as(usize, @intCast(next_idx)) >= self.doc.nodes.items.len) return null;
        if (self.doc.nodes.items[next_idx].prev_sibling != self.index) return null;
        return self.doc.nodeAt(next_idx);
    }

    pub fn prevSibling(self: @This()) ?Node {
        return self.doc.nodeAt(self.raw().prev_sibling);
    }

    pub fn parentNode(self: @This()) ?Node {
        return self.doc.nodeAt(self.raw().parent);
    }

    pub fn getAttributeValueRaw(self: @This(), name: []const u8) ?[]const u8 {
        const idx = self.findAttributeIndex(name) orelse return null;
        return self.doc.attrs.items[idx].value.slice(self.doc.source);
    }

    pub fn getAttributeValue(self: @This(), alloc: std.mem.Allocator, name: []const u8) ValueError!?[]u8 {
        const raw_value = self.getAttributeValueRaw(name) orelse return null;
        return try self.doc.decodeValueAlloc(alloc, raw_value);
    }

    pub fn firstAttribute(self: @This()) ?Attribute {
        const node_raw = self.raw();
        if (node_raw.attr_len == 0) return null;
        return .{ .doc = self.doc, .index = node_raw.attr_start };
    }

    /// Returns a borrowed raw text slice when the subtree's text content is
    /// exactly one contiguous text node; otherwise returns null.
    pub fn innerTextRaw(self: @This()) ?[]const u8 {
        if (self.kind == .text) return self.valueRawSlice();

        const node_raw = self.raw();
        var first: ?[]const u8 = null;
        var idx = self.index + 1;
        while (idx <= node_raw.subtree_end and idx < self.doc.nodes.items.len) : (idx += 1) {
            const child = self.doc.nodes.items[idx];
            if (child.kind != .text) continue;
            if (first != null) return null;
            first = child.value.slice(self.doc.source);
        }
        return first orelse "";
    }

    /// Materializes subtree text into a dedicated decoded allocation.
    pub fn innerText(self: @This(), alloc: std.mem.Allocator) ValueError![]u8 {
        if (self.kind == .text) return self.value(alloc);

        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(alloc);

        const node_raw = self.raw();
        var idx = self.index + 1;
        while (idx <= node_raw.subtree_end and idx < self.doc.nodes.items.len) : (idx += 1) {
            const child = self.doc.nodes.items[idx];
            if (child.kind != .text) continue;
            try self.doc.appendDecodedValue(&out, alloc, child.value.slice(self.doc.source));
        }
        return out.toOwnedSlice(alloc);
    }

    pub fn matchesSelector(self: @This(), selector: []const u8) bool {
        return selectorMatches(self, selector);
    }

    pub fn querySelector(self: @This(), selector: []const u8) ?Node {
        var idx = self.index + 1;
        const end = self.raw().subtree_end;
        while (idx <= end and idx < self.doc.nodes.items.len) : (idx += 1) {
            const child = self.doc.nodeAt(idx).?;
            if (child.kind == .element and child.matchesSelector(selector)) return child;
        }
        return null;
    }

    pub fn querySelectorAll(self: @This(), alloc: std.mem.Allocator, selector: []const u8) std.mem.Allocator.Error![]Node {
        var out = std.ArrayList(Node).empty;
        errdefer out.deinit(alloc);

        var idx = self.index + 1;
        const end = self.raw().subtree_end;
        while (idx <= end and idx < self.doc.nodes.items.len) : (idx += 1) {
            const child = self.doc.nodeAt(idx).?;
            if (child.kind == .element and child.matchesSelector(selector)) try out.append(alloc, child);
        }
        return out.toOwnedSlice(alloc);
    }
};

pub const Document = struct {
    allocator: std.mem.Allocator,
    source: []const u8 = "",
    parse_mode: ParseMode = .turbo,
    expand_dtd_entities: bool = false,
    max_entity_value_len: usize = 4096,
    /// Largest input size we have reserved arrays for so repeated parses can
    /// reuse capacity instead of re-growing on every call.
    reserved_input_hint_len: usize = 0,

    nodes: std.ArrayList(RawNode) = .empty,
    attrs: std.ArrayList(RawAttribute) = .empty,
    parse_stack: std.ArrayList(ParseStackEntry) = .empty,
    entity_map: std.StringHashMap([]u8),

    pub fn init(allocator: std.mem.Allocator) Document {
        return .{
            .allocator = allocator,
            .entity_map = std.StringHashMap([]u8).init(allocator),
        };
    }

    pub fn deinit(self: *Document) void {
        self.clearEntityMap();
        self.entity_map.deinit();
        self.nodes.deinit(self.allocator);
        self.attrs.deinit(self.allocator);
        self.parse_stack.deinit(self.allocator);
    }

    pub fn clear(self: *Document) void {
        self.clearEntityMap();
        self.source = "";
        self.parse_mode = .turbo;
        self.expand_dtd_entities = false;
        self.max_entity_value_len = 4096;
        self.nodes.items.len = 0;
        self.attrs.items.len = 0;
        self.parse_stack.items.len = 0;
    }

    pub fn parse(noalias self: *Document, noalias input: []const u8, comptime opts: ParseOptions) ParseError!void {
        self.clear();
        self.source = input;
        self.parse_mode = opts.mode;
        self.expand_dtd_entities = opts.expand_dtd_entities;
        self.max_entity_value_len = opts.max_entity_value_len;
        try parser.parseInto(self, input, opts);
    }

    pub fn parseDiagnostic(noalias self: *Document, noalias input: []const u8, comptime opts: ParseOptions) ?ParseDiagnostic {
        self.parse(input, opts) catch |err| return .{
            .err = err,
            .offset = parser.lastErrorOffset(),
            .source = input,
        };
        return null;
    }

    fn clearEntityMap(self: *Document) void {
        var it = self.entity_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.entity_map.clearRetainingCapacity();
    }

    fn decodeValueAlloc(self: *const Document, alloc: std.mem.Allocator, raw: []const u8) ValueError![]u8 {
        if (!self.expand_dtd_entities) {
            return entities.decodeAlloc(alloc, raw, self.parse_mode == .strict);
        }
        return entities.decodeAllocWithEntityMap(alloc, raw, self.parse_mode == .strict, &self.entity_map);
    }

    fn appendDecodedValue(self: *const Document, out: *std.ArrayList(u8), alloc: std.mem.Allocator, raw: []const u8) ValueError!void {
        if (!self.expand_dtd_entities) {
            return entities.appendDecoded(out, alloc, raw, self.parse_mode == .strict);
        }
        return entities.appendDecodedWithEntityMap(out, alloc, raw, self.parse_mode == .strict, &self.entity_map);
    }

    /// Scans the internal subset for simple general-entity declarations and
    /// stores owned decoded values for later decoded text/attribute access.
    pub fn registerDoctypeEntities(self: *Document, doctype_value: []const u8) ParseError!void {
        const subset_start = std.mem.indexOfScalar(u8, doctype_value, '[') orelse return;
        const subset_end = std.mem.lastIndexOfScalar(u8, doctype_value, ']') orelse return;
        if (subset_end <= subset_start + 1) return;

        const subset = doctype_value[subset_start + 1 .. subset_end];
        var i: usize = 0;
        while (i < subset.len) {
            const decl_rel = std.mem.indexOfPos(u8, subset, i, "<!ENTITY") orelse break;
            i = decl_rel + "<!ENTITY".len;

            while (i < subset.len and tables.isWhitespace(subset[i])) : (i += 1) {}
            if (i >= subset.len) return error.UnexpectedEndOfData;

            if (subset[i] == '%') {
                const end = findMarkupDeclEnd(subset, i + 1) orelse return error.UnexpectedEndOfData;
                i = end + 1;
                continue;
            }

            if (!tables.isNameStart(subset[i])) {
                const end = findMarkupDeclEnd(subset, i) orelse return error.UnexpectedEndOfData;
                i = end + 1;
                continue;
            }

            const name_start = i;
            i += 1;
            while (i < subset.len and tables.isNameChar(subset[i])) : (i += 1) {}
            const name = subset[name_start..i];

            while (i < subset.len and tables.isWhitespace(subset[i])) : (i += 1) {}
            if (i >= subset.len) return error.UnexpectedEndOfData;

            const quote = subset[i];
            if (quote != '\'' and quote != '"') {
                const end = findMarkupDeclEnd(subset, i) orelse return error.UnexpectedEndOfData;
                i = end + 1;
                continue;
            }

            i += 1;
            const value_start = i;
            while (i < subset.len and subset[i] != quote) : (i += 1) {}
            if (i >= subset.len) return error.UnexpectedEndOfData;

            const raw_value = subset[value_start..i];
            const expanded = if (self.expand_dtd_entities)
                try entities.decodeAllocWithEntityMap(self.allocator, raw_value, self.parse_mode == .strict, &self.entity_map)
            else
                try self.allocator.dupe(u8, raw_value);
            errdefer self.allocator.free(expanded);

            if (expanded.len > self.max_entity_value_len) return error.EntityValueTooLarge;

            const owned_name = try self.allocator.dupe(u8, name);
            errdefer self.allocator.free(owned_name);

            const gop = try self.entity_map.getOrPut(owned_name);
            if (gop.found_existing) {
                self.allocator.free(gop.key_ptr.*);
                self.allocator.free(gop.value_ptr.*);
            }
            gop.key_ptr.* = owned_name;
            gop.value_ptr.* = expanded;

            const end = findMarkupDeclEnd(subset, i + 1) orelse return error.UnexpectedEndOfData;
            i = end + 1;
        }
    }

    pub fn root(self: *const Document) ?Node {
        return @constCast(self).nodeAt(0);
    }

    pub fn nodeAt(self: *const Document, idx: IndexInt) ?Node {
        if (idx == InvalidIndex or @as(usize, @intCast(idx)) >= self.nodes.items.len) return null;
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
        if (input_len <= self.reserved_input_hint_len) return;

        const est_nodes = @max(@as(usize, 16), input_len / 14 + 8);
        const est_attrs = @max(@as(usize, 16), input_len / 32 + 8);
        const est_stack = @max(@as(usize, 8), input_len / 512 + 8);

        if (est_nodes > self.nodes.capacity) try self.nodes.ensureTotalCapacity(self.allocator, est_nodes);
        if (est_attrs > self.attrs.capacity) try self.attrs.ensureTotalCapacity(self.allocator, est_attrs);
        if (est_stack > self.parse_stack.capacity) try self.parse_stack.ensureTotalCapacity(self.allocator, est_stack);
        self.reserved_input_hint_len = input_len;
    }
};

fn findMarkupDeclEnd(input: []const u8, start: usize) ?usize {
    var i = start;
    var quote: u8 = 0;
    while (i < input.len) : (i += 1) {
        const c = input[i];
        if (quote != 0) {
            if (c == quote) quote = 0;
            continue;
        }
        if (c == '\'' or c == '"') {
            quote = c;
            continue;
        }
        if (c == '>') return i;
    }
    return null;
}

fn selectorMatches(node: Node, selector: []const u8) bool {
    if (selector.len == 0 or node.kind != .element) return false;

    var rest = selector;
    if (rest[0] != '*' and rest[0] != '#' and rest[0] != '.' and rest[0] != '[') {
        var end: usize = 0;
        while (end < rest.len and rest[end] != '#' and rest[end] != '.' and rest[end] != '[') : (end += 1) {}
        if (!std.mem.eql(u8, node.nameSlice(), rest[0..end])) return false;
        rest = rest[end..];
    } else if (rest[0] == '*') {
        rest = rest[1..];
    }

    while (rest.len != 0) {
        switch (rest[0]) {
            '#' => {
                const part = selectorPart(rest[1..]);
                const id = node.getAttributeValueRaw("id") orelse return false;
                if (!std.mem.eql(u8, id, part.value)) return false;
                rest = part.rest;
            },
            '.' => {
                const part = selectorPart(rest[1..]);
                const class = node.getAttributeValueRaw("class") orelse return false;
                if (!hasClassToken(class, part.value)) return false;
                rest = part.rest;
            },
            '[' => {
                const close = std.mem.indexOfScalar(u8, rest, ']') orelse return false;
                const expr = rest[1..close];
                if (std.mem.indexOfScalar(u8, expr, '=')) |eq| {
                    const name = trimAscii(expr[0..eq]);
                    const want = trimQuotes(trimAscii(expr[eq + 1 ..]));
                    const got = node.getAttributeValueRaw(name) orelse return false;
                    if (!std.mem.eql(u8, got, want)) return false;
                } else if (node.getAttributeValueRaw(trimAscii(expr)) == null) return false;
                rest = rest[close + 1 ..];
            },
            else => return false,
        }
    }
    return true;
}

const SelectorPart = struct {
    value: []const u8,
    rest: []const u8,
};

fn selectorPart(input: []const u8) SelectorPart {
    var end: usize = 0;
    while (end < input.len and input[end] != '#' and input[end] != '.' and input[end] != '[') : (end += 1) {}
    return .{ .value = input[0..end], .rest = input[end..] };
}

fn hasClassToken(class: []const u8, token: []const u8) bool {
    if (token.len == 0) return false;
    var i: usize = 0;
    while (i < class.len) {
        while (i < class.len and tables.isWhitespace(class[i])) : (i += 1) {}
        const start = i;
        while (i < class.len and !tables.isWhitespace(class[i])) : (i += 1) {}
        if (std.mem.eql(u8, class[start..i], token)) return true;
    }
    return false;
}

fn trimAscii(input: []const u8) []const u8 {
    var start: usize = 0;
    var end = input.len;
    while (start < end and tables.isWhitespace(input[start])) : (start += 1) {}
    while (end > start and tables.isWhitespace(input[end - 1])) : (end -= 1) {}
    return input[start..end];
}

fn trimQuotes(input: []const u8) []const u8 {
    if (input.len >= 2 and ((input[0] == '\'' and input[input.len - 1] == '\'') or (input[0] == '"' and input[input.len - 1] == '"'))) {
        return input[1 .. input.len - 1];
    }
    return input;
}

test "Types(options) exposes concrete DOM types" {
    const opts: ParseOptions = .{};
    const types = Types(opts);
    try std.testing.expectEqual(Span, types.Span);
    try std.testing.expectEqual(RawNode, types.RawNode);
    try std.testing.expectEqual(Node, types.Node);
    try std.testing.expectEqual(RawAttribute, types.RawAttribute);
    try std.testing.expectEqual(Attribute, types.Attribute);
    try std.testing.expectEqual(Document, types.Document);
    try std.testing.expectEqual(IndexInt, types.IndexInt);
}

test "Span helpers expose slices and lengths" {
    const opts: ParseOptions = .{};
    const SpanType = Types(opts).Span;
    const buf = "abcdef";
    const span: SpanType = .{ .start = 1, .end = 4 };
    try std.testing.expectEqual(@as(IndexInt, 3), span.len());
    try std.testing.expect(!span.isEmpty());
    try std.testing.expectEqualStrings("bcd", span.slice(buf));

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

    const xml = "<r a='&amp;'>&lt;x&gt;</r>";
    try doc.parse(xml, .{ .mode = .strict });
    try std.testing.expect(doc.root() != null);
    try std.testing.expect(doc.nodeAt(1) != null);

    const root = doc.nodeAt(1).?;
    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer std.testing.allocator.free(attr);
    const text = try root.firstChild().?.value(std.testing.allocator);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("&", attr);
    try std.testing.expectEqualStrings("<x>", text);
    try std.testing.expectEqualStrings("&amp;", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("&lt;x&gt;", root.firstChild().?.valueRawSlice());
    try std.testing.expectEqual(@as(IndexInt, 0), root.parentNode().?.index);
    try std.testing.expectEqual(root.index, root.firstChild().?.parentNode().?.index);

    doc.clear();
    try std.testing.expect(doc.root() == null);
    try std.testing.expectEqualStrings("", doc.source);
    try std.testing.expectEqual(@as(usize, 0), doc.nodes.items.len);
    try std.testing.expectEqual(@as(usize, 0), doc.attrs.items.len);
}

test "lazy namespace helpers split names and resolve inherited xmlns" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse("<r xmlns='urn:default' xmlns:x='urn:x'><x:item x:id='1'/></r>", .{ .mode = .strict });

    const root_node = doc.nodeAt(1).?;
    const item = root_node.firstChild().?;
    const attr = item.firstAttribute().?;

    try std.testing.expect(root_node.namespacePrefix() == null);
    try std.testing.expectEqualStrings("r", root_node.localName());
    try std.testing.expectEqualStrings("urn:default", root_node.namespaceUri().?);
    try std.testing.expectEqualStrings("x", item.namespacePrefix().?);
    try std.testing.expectEqualStrings("item", item.localName());
    try std.testing.expectEqualStrings("urn:x", item.namespaceUri().?);
    try std.testing.expectEqualStrings("x", attr.namespacePrefix().?);
    try std.testing.expectEqualStrings("id", attr.localName());
}

test "selector query helpers match tag id class and attributes" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse("<r><item id='a' class='hot new' data-x='1'/><item class='cold'/></r>", .{ .mode = .strict });

    const r = doc.nodeAt(1).?;
    try std.testing.expect(r.querySelector("item.hot") != null);
    try std.testing.expectEqualStrings("a", r.querySelector("#a").?.getAttributeValueRaw("id").?);
    try std.testing.expect(r.querySelector("item[data-x=1]") != null);

    const items = try r.querySelectorAll(std.testing.allocator, "item");
    defer std.testing.allocator.free(items);
    try std.testing.expectEqual(@as(usize, 2), items.len);
    try std.testing.expect(items[1].matchesSelector("item.cold"));
}

test "parse diagnostics report offset location and context lazily" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    const diag = doc.parseDiagnostic("<r>\n  <1/>", .{ .mode = .strict }) orelse return error.TestUnexpectedResult;
    const loc = diag.location();

    try std.testing.expectEqual(ParseError.ExpectedElementName, diag.err);
    try std.testing.expectEqual(@as(usize, 2), loc.line);
    try std.testing.expectEqual(@as(usize, 4), loc.column);
    try std.testing.expect(std.mem.indexOf(u8, diag.context(8), "<1") != null);
}

test "registerDoctypeEntities handles double-quoted values and replacements" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    doc.expand_dtd_entities = true;
    doc.parse_mode = .strict;

    try doc.registerDoctypeEntities("[<!ENTITY a \"one\"><!ENTITY a 'two'>]");
    try std.testing.expectEqual(@as(usize, 1), doc.entity_map.count());
    try std.testing.expectEqualStrings("two", doc.entity_map.get("a").?);
}
