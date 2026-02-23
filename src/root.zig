const std = @import("std");

pub const Document = @import("xml/document.zig").Document;
pub const Node = @import("xml/document.zig").Node;
pub const Attribute = @import("xml/document.zig").Attribute;
pub const Span = @import("xml/document.zig").Span;
pub const NodeType = @import("xml/document.zig").NodeType;
pub const ParseMode = @import("xml/document.zig").ParseMode;
pub const ParseOptions = @import("xml/document.zig").ParseOptions;
pub const ParseError = @import("xml/document.zig").ParseError;
pub const InvalidIndex = @import("xml/document.zig").InvalidIndex;

pub fn bufferedPrint() !void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("fastxml: run `zig build test`\n", .{});
    try stdout.flush();
}

test "smoke: parse nested nodes and attributes" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    var src = "<root id='r'><child a='1'>text</child><child a='2'/></root>".*;
    try doc.parse(&src, .{});

    try std.testing.expectEqual(@as(usize, 5), doc.nodes.items.len);
    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.element, root.kind);
    try std.testing.expectEqualStrings("root", root.nameSlice());
    try std.testing.expectEqualStrings("r", root.getAttributeValue("id").?);

    const first_child = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("child", first_child.nameSlice());
    try std.testing.expectEqualStrings("1", first_child.getAttributeValue("a").?);

    const text = first_child.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.text, text.kind);
    try std.testing.expectEqualStrings("text", text.valueSlice());
}

test "misc nodes enabled" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    var src = "<?xml version='1.0'?><root><!--c--><![CDATA[x]]><?p q?><!DOCTYPE root [<!ELEMENT root ANY>]></root>".*;
    try doc.parse(&src, .{ .mode = .strict, .include_misc_nodes = true });

    var saw_comment = false;
    var saw_cdata = false;
    var saw_decl = false;
    var saw_pi = false;
    var saw_doctype = false;

    for (doc.nodes.items) |n| {
        switch (n.kind) {
            .comment => saw_comment = true,
            .cdata => saw_cdata = true,
            .declaration => saw_decl = true,
            .pi => saw_pi = true,
            .doctype => saw_doctype = true,
            else => {},
        }
    }

    try std.testing.expect(saw_comment);
    try std.testing.expect(saw_cdata);
    try std.testing.expect(saw_decl);
    try std.testing.expect(saw_pi);
    try std.testing.expect(saw_doctype);
}

test "strict mismatched close tag fails" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    var src = "<a><b></a>".*;
    try std.testing.expectError(ParseError.InvalidClosingTagName, doc.parse(&src, .{ .mode = .strict, .validate_closing_tags = true }));
}

test "turbo mode builds dom by default" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    var src = "<root><a>v</a><b x='1'/></root>".*;
    try doc.parse(&src, .{
        .mode = .turbo,
        .store_parent_pointers = false,
        .include_misc_nodes = false,
    });

    try std.testing.expectEqual(@as(usize, 5), doc.nodes.items.len);
    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.element, root.kind);
    try std.testing.expectEqualStrings("root", root.nameSlice());
    try std.testing.expectEqualStrings("1", root.firstChild().?.nextSibling().?.getAttributeValue("x").?);
}

test "entity decode on parse" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    var src = "<r a='&amp;&#x41;'>&lt;ok&gt;&#65;</r>".*;
    try doc.parse(&src, .{ .mode = .strict, .decode_entities_on_parse = true });

    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&A", root.getAttributeValue("a").?);

    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("<ok>A", text.valueSlice());
}

test "normalize text whitespace" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    var src = "<r> a\n\t b   c </r>".*;
    try doc.parse(&src, .{ .normalize_text_whitespace = true });

    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(" a b c ", text.valueSlice());
}

test "store parent pointers option" {
    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();

    var src = "<a><b/></a>".*;
    try doc.parse(&src, .{ .store_parent_pointers = true });
    const b = doc.nodeAt(2) orelse return error.TestUnexpectedResult;
    try std.testing.expect(b.parentNode() != null);

    try doc.parse(&src, .{ .store_parent_pointers = false });
    const b2 = doc.nodeAt(2) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(?*const Node, null), b2.parentNode());
}

test "attribute-heavy element parses and preserves lookups" {
    var xml = std.ArrayList(u8).empty;
    defer xml.deinit(std.testing.allocator);

    try xml.appendSlice(std.testing.allocator, "<root");
    const w = xml.writer(std.testing.allocator);
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        try w.print(" a{d}='v{d}'", .{ i, i });
    }
    try xml.appendSlice(std.testing.allocator, "></root>");

    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse(xml.items, .{ .mode = .strict, .validate_closing_tags = true });

    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("v0", root.getAttributeValue("a0").?);
    try std.testing.expectEqualStrings("v63", root.getAttributeValue("a63").?);
    try std.testing.expectEqual(@as(u32, 64), root.attr_len);
}

test "strict deep balanced close tags" {
    var xml = std.ArrayList(u8).empty;
    defer xml.deinit(std.testing.allocator);

    try xml.appendSlice(std.testing.allocator, "<r>");
    const w = xml.writer(std.testing.allocator);
    var i: usize = 0;
    while (i < 128) : (i += 1) {
        try w.print("<n{d}>", .{i});
    }
    i = 128;
    while (i > 0) {
        i -= 1;
        try w.print("</n{d}>", .{i});
    }
    try xml.appendSlice(std.testing.allocator, "</r>");

    var doc = Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.parse(xml.items, .{
        .mode = .strict,
        .validate_closing_tags = true,
        .store_parent_pointers = true,
    });

    try std.testing.expectEqual(@as(usize, 129), countKind(&doc, .element));
}

fn countKind(doc: *const Document, kind: NodeType) usize {
    var n: usize = 0;
    for (doc.nodes.items) |node| {
        if (node.kind == kind) n += 1;
    }
    return n;
}
