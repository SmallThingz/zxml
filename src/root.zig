const std = @import("std");
const document_mod = @import("document.zig");
const parser_mod = @import("parser.zig");
const scanner_mod = @import("scanner.zig");
const tables_mod = @import("tables.zig");
const entities_mod = @import("entities.zig");

pub const NodeType = document_mod.NodeType;
pub const ParseMode = document_mod.ParseMode;
pub const ParseOptions = document_mod.ParseOptions;
pub const ParseError = document_mod.ParseError;
pub const InvalidIndex = document_mod.InvalidIndex;

pub fn Types(comptime options: ParseOptions) type {
    return document_mod.Types(options);
}

fn ParsedDoc(comptime opts: ParseOptions) type {
    const DocumentType = Types(opts).Document;

    return struct {
        doc: DocumentType,
        buf: []u8,

        fn deinit(self: *@This()) void {
            self.doc.deinit();
            std.testing.allocator.free(self.buf);
        }
    };
}

fn parseTestDoc(input: []const u8, comptime opts: ParseOptions) !ParsedDoc(opts) {
    const DocumentType = Types(opts).Document;
    const buf = try std.testing.allocator.dupe(u8, input);
    errdefer std.testing.allocator.free(buf);

    var doc = DocumentType.init(std.testing.allocator);
    errdefer doc.deinit();
    try doc.parse(buf, opts);

    return .{
        .doc = doc,
        .buf = buf,
    };
}

fn initDoc(comptime opts: ParseOptions) Types(opts).Document {
    const DocumentType = Types(opts).Document;
    return DocumentType.init(std.testing.allocator);
}

fn countKind(doc: anytype, kind: NodeType) usize {
    var n: usize = 0;
    for (doc.nodes.items) |node| {
        if (node.kind == kind) n += 1;
    }
    return n;
}

fn findFirstKind(doc: anytype, kind: NodeType) ?std.meta.Child(@TypeOf(doc.nodeAt(0))) {
    for (doc.nodes.items, 0..) |node, i| {
        if (node.kind == kind) return doc.nodeAt(@intCast(i));
    }
    return null;
}

test "Types(options) matches document module type factory" {
    const opts: ParseOptions = .{};
    const root_types = Types(opts);
    const doc_types = document_mod.Types(opts);
    try std.testing.expectEqual(doc_types.Document, root_types.Document);
    try std.testing.expectEqual(doc_types.Node, root_types.Node);
    try std.testing.expectEqual(doc_types.Attribute, root_types.Attribute);
    try std.testing.expectEqual(doc_types.Span, root_types.Span);
}

test "smoke: parse nested nodes and attributes" {
    var parsed = try parseTestDoc("<root id='r'><child a='1'>text</child><child a='2'/></root>", .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 5), parsed.doc.nodes.items.len);
    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
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

test "root node is document" {
    var parsed = try parseTestDoc("<root/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.root() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.document, root.kind);
}

test "document first child is the root element" {
    var parsed = try parseTestDoc("<root/>", .{});
    defer parsed.deinit();

    const doc_root = parsed.doc.root() orelse return error.TestUnexpectedResult;
    const root = doc_root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("root", root.nameSlice());
}

test "sibling nextSibling chain traverses in document order" {
    var parsed = try parseTestDoc("<r><a/><b/><c/></r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const a = root.firstChild() orelse return error.TestUnexpectedResult;
    const b = a.nextSibling() orelse return error.TestUnexpectedResult;
    const c = b.nextSibling() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("a", a.nameSlice());
    try std.testing.expectEqualStrings("b", b.nameSlice());
    try std.testing.expectEqualStrings("c", c.nameSlice());
    try std.testing.expect(c.nextSibling() == null);
}

test "sibling prevSibling chain traverses backwards" {
    var parsed = try parseTestDoc("<r><a/><b/><c/></r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const c = root.lastChild() orelse return error.TestUnexpectedResult;
    const b = c.prevSibling() orelse return error.TestUnexpectedResult;
    const a = b.prevSibling() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("c", c.nameSlice());
    try std.testing.expectEqualStrings("b", b.nameSlice());
    try std.testing.expectEqualStrings("a", a.nameSlice());
    try std.testing.expect(a.prevSibling() == null);
}

test "lastChild returns the final child" {
    var parsed = try parseTestDoc("<r><a/><b/><c/></r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const last = root.lastChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("c", last.nameSlice());
}

test "text nodes are leaves" {
    var parsed = try parseTestDoc("<r>text</r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.text, text.kind);
    try std.testing.expect(text.firstChild() == null);
}

test "mixed content keeps text element text element text order" {
    var parsed = try parseTestDoc("<r>head<a/>tail<b/>end</r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text1 = root.firstChild() orelse return error.TestUnexpectedResult;
    const a = text1.nextSibling() orelse return error.TestUnexpectedResult;
    const text2 = a.nextSibling() orelse return error.TestUnexpectedResult;
    const b = text2.nextSibling() orelse return error.TestUnexpectedResult;
    const text3 = b.nextSibling() orelse return error.TestUnexpectedResult;

    try std.testing.expectEqualStrings("head", text1.valueSlice());
    try std.testing.expectEqualStrings("a", a.nameSlice());
    try std.testing.expectEqualStrings("tail", text2.valueSlice());
    try std.testing.expectEqualStrings("b", b.nameSlice());
    try std.testing.expectEqualStrings("end", text3.valueSlice());
}

test "whitespace-only text is skipped by default" {
    var parsed = try parseTestDoc("<r> \n\t </r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expect(root.firstChild() == null);
}

test "mixed whitespace text is preserved by default" {
    var parsed = try parseTestDoc("<r> a\n\t b   c </r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(" a\n\t b   c ", text.valueSlice());
}

test "drop_whitespace_text_nodes false keeps pure whitespace nodes" {
    var parsed = try parseTestDoc("<r> \n\t </r>", .{ .drop_whitespace_text_nodes = false });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.text, text.kind);
    try std.testing.expectEqualStrings(" \n\t ", text.valueSlice());
}

test "default whitespace dropping skips indentation between child elements" {
    var parsed = try parseTestDoc("<r>\n  <a/>\n  <b/>\n</r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const a = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.element, a.kind);
    try std.testing.expectEqualStrings("a", a.nameSlice());

    const b = a.nextSibling() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.element, b.kind);
    try std.testing.expectEqualStrings("b", b.nameSlice());
    try std.testing.expect(b.nextSibling() == null);
}

test "entity decode on parse" {
    var parsed = try parseTestDoc("<r a='&amp;&#x41;'>&lt;ok&gt;&#65;</r>", .{ .mode = .strict, .decode_entities_on_parse = true });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&A", root.getAttributeValue("a").?);

    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("<ok>A", text.valueSlice());
}

test "decode disabled leaves literal entities in text and attributes" {
    var parsed = try parseTestDoc("<r a='&amp;'>&lt;ok&gt;</r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&amp;", root.getAttributeValue("a").?);
    try std.testing.expectEqualStrings("&lt;ok&gt;", root.firstChild().?.valueSlice());
}

test "decode preserves surrounding whitespace" {
    var parsed = try parseTestDoc("<r> a\n&amp;\t b  </r>", .{
        .mode = .strict,
        .decode_entities_on_parse = true,
    });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(" a\n&\t b  ", text.valueSlice());
}

test "misc nodes enabled parses declaration nodes" {
    var parsed = try parseTestDoc("<?xml version='1.0'?><root/>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .declaration) != null);
}

test "misc nodes enabled parses comment nodes" {
    var parsed = try parseTestDoc("<root><!--c--></root>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .comment) != null);
}

test "misc nodes enabled parses cdata nodes" {
    var parsed = try parseTestDoc("<root><![CDATA[x]]></root>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .cdata) != null);
}

test "misc nodes enabled parses processing instructions" {
    var parsed = try parseTestDoc("<root><?p q?></root>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .pi) != null);
}

test "misc nodes enabled parses doctypes" {
    var parsed = try parseTestDoc("<!DOCTYPE root [<!ELEMENT root ANY>]><root/>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .doctype) != null);
}

test "misc nodes disabled omits declaration comment cdata pi and doctype" {
    var parsed = try parseTestDoc("<?xml version='1.0'?><!DOCTYPE root [<!ELEMENT root ANY>]><root><!--c--><![CDATA[x]]><?p q?></root>", .{
        .mode = .strict,
        .include_misc_nodes = false,
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 0), countKind(&parsed.doc, .declaration));
    try std.testing.expectEqual(@as(usize, 0), countKind(&parsed.doc, .doctype));
    try std.testing.expectEqual(@as(usize, 0), countKind(&parsed.doc, .comment));
    try std.testing.expectEqual(@as(usize, 0), countKind(&parsed.doc, .cdata));
    try std.testing.expectEqual(@as(usize, 0), countKind(&parsed.doc, .pi));
}

test "declaration stores target and value" {
    var parsed = try parseTestDoc("<?xml version='1.0' encoding='utf-8'?><root/>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    const decl = findFirstKind(&parsed.doc, .declaration) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("xml", decl.nameSlice());
    try std.testing.expect(std.mem.indexOf(u8, decl.valueSlice(), "version='1.0'") != null);
}

test "processing instruction stores target and value" {
    var parsed = try parseTestDoc("<root><?build target='bench'?></root>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    const pi = findFirstKind(&parsed.doc, .pi) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("build", pi.nameSlice());
    try std.testing.expectEqualStrings("target='bench'", pi.valueSlice());
}

test "comment nodes expose their value slice" {
    var parsed = try parseTestDoc("<root><!--hello--></root>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    const comment = findFirstKind(&parsed.doc, .comment) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("hello", comment.valueSlice());
}

test "cdata nodes expose their value slice" {
    var parsed = try parseTestDoc("<root><![CDATA[a < b && c]]></root>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    const cdata = findFirstKind(&parsed.doc, .cdata) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("a < b && c", cdata.valueSlice());
}

test "doctype preserves internal subset text" {
    var parsed = try parseTestDoc("<!DOCTYPE root [<!ELEMENT root ANY><!ATTLIST root id CDATA #IMPLIED>]><root/>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    const doctype = findFirstKind(&parsed.doc, .doctype) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, doctype.valueSlice(), "<!ELEMENT root ANY>") != null);
    try std.testing.expect(std.mem.indexOf(u8, doctype.valueSlice(), "<!ATTLIST root") != null);
}

test "turbo mismatched close tag without validation is tolerated" {
    var parsed = try parseTestDoc("<a><b></a>", .{ .mode = .turbo });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.doc.nodes.items.len);
    try std.testing.expectEqualStrings("a", parsed.doc.nodeAt(1).?.nameSlice());
    try std.testing.expectEqualStrings("b", parsed.doc.nodeAt(2).?.nameSlice());
}

test "strict mismatched close tag without validation is tolerated" {
    var parsed = try parseTestDoc("<a><b></a>", .{ .mode = .strict });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.doc.nodes.items.len);
    try std.testing.expectEqualStrings("a", parsed.doc.nodeAt(1).?.nameSlice());
    try std.testing.expectEqualStrings("b", parsed.doc.nodeAt(2).?.nameSlice());
}

test "strict mismatched close tag validation fails" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<a><b></a>".*;
    try std.testing.expectError(ParseError.InvalidClosingTagName, doc.parse(&src, .{ .mode = .strict, .validate_closing_tags = true }));
}

test "turbo validate closing tags also fails on mismatch" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<a><b></a>".*;
    try std.testing.expectError(ParseError.InvalidClosingTagName, doc.parse(&src, .{ .mode = .turbo, .validate_closing_tags = true }));
}

test "strict mode tolerates EOF with open elements by default" {
    var parsed = try parseTestDoc("<a><b>", .{ .mode = .strict });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.doc.nodes.items.len);
    try std.testing.expectEqualStrings("a", parsed.doc.nodeAt(1).?.nameSlice());
    try std.testing.expectEqualStrings("b", parsed.doc.nodeAt(2).?.nameSlice());
}

test "require_closed_elements_on_eof enforces balanced open elements" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<a><b>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src, .{
        .mode = .strict,
        .require_closed_elements_on_eof = true,
    }));
}

test "turbo mode builds dom by default" {
    var parsed = try parseTestDoc("<root><a>v</a><b x='1'/></root>", .{
        .mode = .turbo,
        .include_misc_nodes = false,
    });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 5), parsed.doc.nodes.items.len);
    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.element, root.kind);
    try std.testing.expectEqualStrings("root", root.nameSlice());
    try std.testing.expectEqualStrings("1", root.firstChild().?.nextSibling().?.getAttributeValue("x").?);
}

test "parent pointers are always available" {
    var parsed = try parseTestDoc("<a><b/></a>", .{});
    defer parsed.deinit();

    const b = parsed.doc.nodeAt(2) orelse return error.TestUnexpectedResult;
    try std.testing.expect(b.parentNode() != null);
    try std.testing.expectEqualStrings("a", b.parentNode().?.nameSlice());
}

test "parent pointers traverse deep chains" {
    var parsed = try parseTestDoc("<a><b><c><d/></c></b></a>", .{});
    defer parsed.deinit();

    const d = parsed.doc.nodeAt(4) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("c", d.parentNode().?.nameSlice());
    try std.testing.expectEqualStrings("b", d.parentNode().?.parentNode().?.nameSlice());
    try std.testing.expectEqualStrings("a", d.parentNode().?.parentNode().?.parentNode().?.nameSlice());
}

test "attribute-heavy element parses and preserves lookups" {
    var xml = std.ArrayList(u8).empty;
    defer xml.deinit(std.testing.allocator);

    try xml.appendSlice(std.testing.allocator, "<root");
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        try xml.print(std.testing.allocator, " a{d}='v{d}'", .{ i, i });
    }
    try xml.appendSlice(std.testing.allocator, "></root>");

    var doc = initDoc(.{});
    defer doc.deinit();
    try doc.parse(xml.items, .{ .mode = .strict, .validate_closing_tags = true });

    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("v0", root.getAttributeValue("a0").?);
    try std.testing.expectEqualStrings("v63", root.getAttributeValue("a63").?);
    try std.testing.expectEqual(@as(u32, 64), root.attr_len);
}

test "firstAttribute returns the first parsed attribute" {
    var parsed = try parseTestDoc("<r a='1' b='2' c='3'/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const attr = root.firstAttribute() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("a", attr.nameSlice());
    try std.testing.expectEqualStrings("1", attr.valueSlice());
}

test "missing attribute lookup returns null" {
    var parsed = try parseTestDoc("<r a='1'/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expect(root.getAttributeValue("missing") == null);
}

test "single and double quoted attributes both parse" {
    var parsed = try parseTestDoc("<r a='1' b=\"2\"/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("1", root.getAttributeValue("a").?);
    try std.testing.expectEqualStrings("2", root.getAttributeValue("b").?);
}

test "quoted attributes tolerate whitespace around the equals sign" {
    var parsed = try parseTestDoc("<r a = '1' b= \"2\" c =\"3\" d= '4'/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("1", root.getAttributeValue("a").?);
    try std.testing.expectEqualStrings("2", root.getAttributeValue("b").?);
    try std.testing.expectEqualStrings("3", root.getAttributeValue("c").?);
    try std.testing.expectEqualStrings("4", root.getAttributeValue("d").?);
}

test "namespace-like element and attribute names parse" {
    var parsed = try parseTestDoc("<ns:root xml:lang='en'><ns:item data.id='7'/></ns:root>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const item = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ns:root", root.nameSlice());
    try std.testing.expectEqualStrings("en", root.getAttributeValue("xml:lang").?);
    try std.testing.expectEqualStrings("ns:item", item.nameSlice());
    try std.testing.expectEqualStrings("7", item.getAttributeValue("data.id").?);
}

test "strict unquoted attributes fail" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<r a=1/>".*;
    try std.testing.expectError(ParseError.ExpectedQuote, doc.parse(&src, .{ .mode = .strict }));
}

test "turbo unquoted attributes parse" {
    var parsed = try parseTestDoc("<r a=1/>", .{ .mode = .turbo });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("1/", root.getAttributeValue("a").?);
}

test "strict unterminated quoted attribute fails" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<r a='x></r>".*;
    try std.testing.expectError(ParseError.ExpectedQuote, doc.parse(&src, .{ .mode = .strict }));
}

test "strict unterminated comment fails" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<r><!--x</r>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src, .{ .mode = .strict }));
}

test "strict unterminated cdata fails" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<r><![CDATA[x</r>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src, .{ .mode = .strict }));
}

test "strict unterminated processing instruction fails" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<r><?build x='1'</r>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src, .{ .mode = .strict }));
}

test "strict unterminated doctype fails" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<!DOCTYPE root [<!ELEMENT root ANY><root/>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src, .{ .mode = .strict }));
}

test "strict invalid numeric entity in text fails" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<r>&#x110000;</r>".*;
    try std.testing.expectError(ParseError.InvalidNumericCharacterEntity, doc.parse(&src, .{ .mode = .strict, .decode_entities_on_parse = true }));
}

test "strict invalid numeric entity in attribute fails" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<r a='&#x110000;'/>".*;
    try std.testing.expectError(ParseError.InvalidNumericCharacterEntity, doc.parse(&src, .{ .mode = .strict, .decode_entities_on_parse = true }));
}

test "strict unterminated entity fails during decode validation" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<r>&amp</r>".*;
    try std.testing.expectError(ParseError.UnterminatedEntity, doc.parse(&src, .{ .mode = .strict, .decode_entities_on_parse = true }));
}

test "turbo invalid numeric entity remains literal during lazy access" {
    var parsed = try parseTestDoc("<r a='&#x110000;'>&#x110000;</r>", .{ .mode = .turbo, .decode_entities_on_parse = true });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&#x110000;", root.getAttributeValue("a").?);
    try std.testing.expectEqualStrings("&#x110000;", root.firstChild().?.valueSlice());
}

test "self-closing siblings traverse correctly" {
    var parsed = try parseTestDoc("<r><a/><b/><c/><d/></r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    var child = root.firstChild() orelse return error.TestUnexpectedResult;
    var count: usize = 0;
    while (true) {
        count += 1;
        child = child.nextSibling() orelse break;
    }
    try std.testing.expectEqual(@as(usize, 4), count);
}

test "document can be reused across parses" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src1 = "<a><b/></a>".*;
    try doc.parse(&src1, .{});
    try std.testing.expectEqual(@as(usize, 3), doc.nodes.items.len);

    var src2 = "<root x='1'>ok</root>".*;
    try doc.parse(&src2, .{ .mode = .strict });
    try std.testing.expectEqual(@as(usize, 3), doc.nodes.items.len);
    try std.testing.expectEqualStrings("root", doc.nodeAt(1).?.nameSlice());
    try std.testing.expectEqualStrings("1", doc.nodeAt(1).?.getAttributeValue("x").?);
    try std.testing.expectEqualStrings("ok", doc.nodeAt(2).?.valueSlice());
}

test "strict deep balanced close tags" {
    var xml = std.ArrayList(u8).empty;
    defer xml.deinit(std.testing.allocator);

    try xml.appendSlice(std.testing.allocator, "<r>");
    var i: usize = 0;
    while (i < 128) : (i += 1) {
        try xml.print(std.testing.allocator, "<n{d}>", .{i});
    }
    i = 128;
    while (i > 0) {
        i -= 1;
        try xml.print(std.testing.allocator, "</n{d}>", .{i});
    }
    try xml.appendSlice(std.testing.allocator, "</r>");

    var doc = initDoc(.{});
    defer doc.deinit();
    try doc.parse(xml.items, .{
        .mode = .strict,
        .validate_closing_tags = true,
    });

    try std.testing.expectEqual(@as(usize, 129), countKind(&doc, .element));
}

fn refAllDeclsRecursive(comptime T: type) void {
    refAllDeclsRecursiveSeen(T, &.{});
}

fn refAllDeclsRecursiveSeen(comptime T: type, comptime seen: []const type) void {
    if (!@import("builtin").is_test) return;
    const name = @typeName(T);
    if (std.mem.eql(u8, name, "std") or
        std.mem.startsWith(u8, name, "std.") or
        std.mem.eql(u8, name, "builtin") or
        std.mem.startsWith(u8, name, "builtin."))
    {
        return;
    }
    inline for (seen) |seen_type| {
        if (seen_type == T) return;
    }

    const next_seen = seen ++ [_]type{T};
    std.testing.refAllDecls(T);

    // Recurse into namespace-style containers only; value-carrying types blow
    // up the traversal without contributing additional declaration coverage.
    inline for (comptime std.meta.declarations(T)) |decl| {
        const decl_value = @field(T, decl.name);
        if (@TypeOf(decl_value) != type) continue;
        const Child = decl_value;
        if (comptime switch (@typeInfo(Child)) {
            .@"struct" => |s| s.fields.len != 0,
            .@"union", .@"enum", .@"opaque" => true,
            else => true,
        }) continue;
        refAllDeclsRecursiveSeen(Child, next_seen);
    }
}

test "refAllDeclsRecursive: every fastxml module compiles all declarations" {
    refAllDeclsRecursive(@This());
    refAllDeclsRecursive(document_mod);
    refAllDeclsRecursive(parser_mod);
    refAllDeclsRecursive(scanner_mod);
    refAllDeclsRecursive(tables_mod);
    refAllDeclsRecursive(entities_mod);
}
