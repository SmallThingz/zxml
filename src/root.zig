const std = @import("std");
const common = @import("common.zig");
const document_mod = @import("document.zig");
const parser_mod = @import("parser.zig");
const scanner_mod = @import("scanner.zig");
const tables_mod = @import("tables.zig");
const entities_mod = @import("entities.zig");
const streaming_mod = @import("streaming.zig");

pub const MaxInputLen = common.MaxLen;
pub const NodeType = document_mod.NodeType;
pub const ParseMode = document_mod.ParseMode;
pub const ParseOptions = document_mod.ParseOptions;
pub const ParseError = document_mod.ParseError;
pub const ParseDiagnostic = document_mod.ParseDiagnostic;
pub const SerializeOptions = document_mod.SerializeOptions;
pub const InvalidIndex = document_mod.InvalidIndex;

pub fn Types(comptime options: ParseOptions) type {
    const doc_types = document_mod.Types(options);
    const stream_types = streaming_mod.Types(options);
    return struct {
        pub const IndexInt = doc_types.IndexInt;
        pub const Span = doc_types.Span;
        pub const RawAttribute = doc_types.RawAttribute;
        pub const Attribute = doc_types.Attribute;
        pub const RawNode = doc_types.RawNode;
        pub const Node = doc_types.Node;
        pub const Document = doc_types.Document;
        pub const StreamingAttribute = stream_types.Attribute;
        pub const StreamingAttributeIterator = stream_types.AttributeIterator;
        pub const StreamingEvent = stream_types.Node;
        pub const StreamingParser = stream_types.Parser;
    };
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
    const stream_types = streaming_mod.Types(opts);
    try std.testing.expectEqual(doc_types.Document, root_types.Document);
    try std.testing.expectEqual(doc_types.Node, root_types.Node);
    try std.testing.expectEqual(doc_types.Attribute, root_types.Attribute);
    try std.testing.expectEqual(doc_types.Span, root_types.Span);
    try std.testing.expectEqual(common.IndexInt, root_types.IndexInt);
    try std.testing.expectEqual(stream_types.Node, root_types.StreamingEvent);
    try std.testing.expectEqual(stream_types.Attribute, root_types.StreamingAttribute);
    try std.testing.expectEqual(stream_types.Parser, root_types.StreamingParser);
}

test "ParseOptions exposes htmlparser-style type helpers and parse" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    try std.testing.expectEqual(Types(opts).Document, opts.Document());

    var doc = try opts.parse(std.testing.allocator, "<root id='r'><child>text</child></root>");
    defer doc.deinit();

    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("root", root.nameSlice());
    try std.testing.expectEqualStrings("r", root.getAttributeValueRaw("id").?);
}

test "smoke: parse nested nodes and attributes" {
    var parsed = try parseTestDoc("<root id='r'><child a='1'>text</child><child a='2'/></root>", .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 5), parsed.doc.nodes.items.len);
    const root = findFirstKind(&parsed.doc, .element) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.element, root.kind);
    try std.testing.expectEqualStrings("root", root.nameSlice());
    try std.testing.expectEqualStrings("r", root.getAttributeValueRaw("id").?);

    const first_child = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("child", first_child.nameSlice());
    try std.testing.expectEqualStrings("1", first_child.getAttributeValueRaw("a").?);

    const text = first_child.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.text, text.kind);
    try std.testing.expectEqualStrings("text", text.valueRawSlice());
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

test "nextSibling skips over descendant subtrees" {
    var parsed = try parseTestDoc("<r><a><x/></a><b/><c/></r>", .{});
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

    try std.testing.expectEqualStrings("head", text1.valueRawSlice());
    try std.testing.expectEqualStrings("a", a.nameSlice());
    try std.testing.expectEqualStrings("tail", text2.valueRawSlice());
    try std.testing.expectEqualStrings("b", b.nameSlice());
    try std.testing.expectEqualStrings("end", text3.valueRawSlice());
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
    try std.testing.expectEqualStrings(" a\n\t b   c ", text.valueRawSlice());
}

test "drop_whitespace_text_nodes false keeps pure whitespace nodes" {
    var parsed = try parseTestDoc("<r> \n\t </r>", .{ .drop_whitespace_text_nodes = false });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(NodeType.text, text.kind);
    try std.testing.expectEqualStrings(" \n\t ", text.valueRawSlice());
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

test "decoded attribute and text helpers allocate decoded bytes" {
    var parsed = try parseTestDoc("<r a='&amp;&#x41;'>&lt;ok&gt;&#65;</r>", .{ .mode = .strict });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer std.testing.allocator.free(attr);
    try std.testing.expectEqualStrings("&A", attr);

    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    const decoded = try text.value(std.testing.allocator);
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings("<ok>A", decoded);
}

test "dtd entity expansion is opt-in and decodes internal entity references" {
    var parsed = try parseTestDoc("<!DOCTYPE r [<!ENTITY safe 'SAFE'>]><r a='&safe;'>&safe;</r>", .{
        .mode = .strict,
        .expand_dtd_entities = true,
    });
    defer parsed.deinit();

    const root = findFirstKind(&parsed.doc, .element) orelse return error.TestUnexpectedResult;
    const attr_raw = root.getAttributeValueRaw("a") orelse return error.TestUnexpectedResult;
    const child = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&safe;", attr_raw);
    try std.testing.expectEqualStrings("&safe;", child.valueRawSlice());

    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer std.testing.allocator.free(attr);
    try std.testing.expectEqualStrings("SAFE", attr);

    const text = try child.value(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("SAFE", text);
}

test "dtd entity expansion max value length is enforced" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src = "<!DOCTYPE r [<!ENTITY big 'abcdef'>]><r>&big;</r>".*;
    try std.testing.expectError(ParseError.EntityValueTooLarge, doc.parse(&src, .{
        .mode = .strict,
        .expand_dtd_entities = true,
        .max_entity_value_len = 4,
    }));
}

test "document reuse clears opt-in dtd entity table" {
    var doc = initDoc(.{});
    defer doc.deinit();

    var src1 = "<!DOCTYPE r [<!ENTITY safe 'SAFE'>]><r>&safe;</r>".*;
    try doc.parse(&src1, .{
        .mode = .strict,
        .expand_dtd_entities = true,
    });
    const first_root = findFirstKind(&doc, .element) orelse return error.TestUnexpectedResult;
    const first = try first_root.firstChild().?.value(std.testing.allocator);
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualStrings("SAFE", first);

    var src2 = "<r>&safe;</r>".*;
    try doc.parse(&src2, .{
        .mode = .turbo,
        .expand_dtd_entities = true,
    });
    const second_root = findFirstKind(&doc, .element) orelse return error.TestUnexpectedResult;
    const second = try second_root.firstChild().?.value(std.testing.allocator);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings("&safe;", second);
}

test "decode disabled leaves literal entities in text and attributes" {
    var parsed = try parseTestDoc("<r a='&amp;'>&lt;ok&gt;</r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&amp;", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("&lt;ok&gt;", root.firstChild().?.valueRawSlice());
}

test "decode disabled never mutates source bytes on value access" {
    var parsed = try parseTestDoc("<r a='&amp;'>&lt;ok&gt;</r>", .{});
    defer parsed.deinit();

    const before = try std.testing.allocator.dupe(u8, parsed.buf);
    defer std.testing.allocator.free(before);

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    _ = root.getAttributeValueRaw("a").?;
    _ = root.firstChild().?.valueRawSlice();

    try std.testing.expectEqualStrings(before, parsed.buf);
}

test "decoded value preserves surrounding whitespace" {
    var parsed = try parseTestDoc("<r> a\n&amp;\t b  </r>", .{ .mode = .strict });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    const decoded = try text.value(std.testing.allocator);
    defer std.testing.allocator.free(decoded);
    try std.testing.expectEqualStrings(" a\n&\t b  ", decoded);
}

test "decoded helpers never mutate source bytes" {
    var parsed = try parseTestDoc("<r a='&amp;'>&lt;ok&gt;</r>", .{ .mode = .strict });
    defer parsed.deinit();

    const before = try std.testing.allocator.dupe(u8, parsed.buf);
    defer std.testing.allocator.free(before);

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer std.testing.allocator.free(attr);
    try std.testing.expectEqualStrings("&", attr);

    const text = try root.firstChild().?.value(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("<ok>", text);
    try std.testing.expectEqualStrings(before, parsed.buf);
}

test "innerTextRaw borrows a single contiguous text node" {
    var parsed = try parseTestDoc("<r>&lt;ok&gt;</r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&lt;ok&gt;", root.innerTextRaw().?);
}

test "innerTextRaw returns null for multi-segment mixed content" {
    var parsed = try parseTestDoc("<r>a<b/>c</r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expect(root.innerTextRaw() == null);
}

test "innerText allocates decoded subtree text" {
    var parsed = try parseTestDoc("<r>a&amp;<b/>c&#33;</r>", .{ .mode = .strict });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = try root.innerText(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("a&c!", text);
}

test "innerText helpers return empty content for textless elements" {
    var parsed = try parseTestDoc("<r><a/></r>", .{ .mode = .strict });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("", root.innerTextRaw().?);
    const text = try root.innerText(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("", text);
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
    try std.testing.expect(std.mem.indexOf(u8, decl.valueRawSlice(), "version='1.0'") != null);
}

test "processing instruction stores target and value" {
    var parsed = try parseTestDoc("<root><?build target='bench'?></root>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    const pi = findFirstKind(&parsed.doc, .pi) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("build", pi.nameSlice());
    try std.testing.expectEqualStrings("target='bench'", pi.valueRawSlice());
}

test "comment nodes expose their value slice" {
    var parsed = try parseTestDoc("<root><!--hello--></root>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    const comment = findFirstKind(&parsed.doc, .comment) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("hello", comment.valueRawSlice());
}

test "cdata nodes expose their value slice" {
    var parsed = try parseTestDoc("<root><![CDATA[a < b && c]]></root>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    const cdata = findFirstKind(&parsed.doc, .cdata) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("a < b && c", cdata.valueRawSlice());
}

test "doctype preserves internal subset text" {
    var parsed = try parseTestDoc("<!DOCTYPE root [<!ELEMENT root ANY><!ATTLIST root id CDATA #IMPLIED>]><root/>", .{ .mode = .strict, .include_misc_nodes = true });
    defer parsed.deinit();

    const doctype = findFirstKind(&parsed.doc, .doctype) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, doctype.valueRawSlice(), "<!ELEMENT root ANY>") != null);
    try std.testing.expect(std.mem.indexOf(u8, doctype.valueRawSlice(), "<!ATTLIST root") != null);
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
    try std.testing.expectEqualStrings("1", root.firstChild().?.nextSibling().?.getAttributeValueRaw("x").?);
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
    try std.testing.expectEqualStrings("v0", root.getAttributeValueRaw("a0").?);
    try std.testing.expectEqualStrings("v63", root.getAttributeValueRaw("a63").?);
    try std.testing.expectEqual(@as(common.IndexInt, 64), root.attr_len);
}

test "firstAttribute returns the first parsed attribute" {
    var parsed = try parseTestDoc("<r a='1' b='2' c='3'/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const attr = root.firstAttribute() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("a", attr.nameSlice());
    try std.testing.expectEqualStrings("1", attr.valueRawSlice());
}

test "missing attribute lookup returns null" {
    var parsed = try parseTestDoc("<r a='1'/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expect(root.getAttributeValueRaw("missing") == null);
}

test "single and double quoted attributes both parse" {
    var parsed = try parseTestDoc("<r a='1' b=\"2\"/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("1", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("2", root.getAttributeValueRaw("b").?);
}

test "quoted attributes tolerate whitespace around the equals sign" {
    var parsed = try parseTestDoc("<r a = '1' b= \"2\" c =\"3\" d= '4'/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("1", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("2", root.getAttributeValueRaw("b").?);
    try std.testing.expectEqualStrings("3", root.getAttributeValueRaw("c").?);
    try std.testing.expectEqualStrings("4", root.getAttributeValueRaw("d").?);
}

test "namespace-like element and attribute names parse" {
    var parsed = try parseTestDoc("<ns:root xml:lang='en'><ns:item data.id='7'/></ns:root>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const item = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("ns:root", root.nameSlice());
    try std.testing.expectEqualStrings("en", root.getAttributeValueRaw("xml:lang").?);
    try std.testing.expectEqualStrings("ns:item", item.nameSlice());
    try std.testing.expectEqualStrings("7", item.getAttributeValueRaw("data.id").?);
}

test "element and attribute names preserve case exactly" {
    var parsed = try parseTestDoc("<Root Attr='x' attr='y'/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("Root", root.nameSlice());
    try std.testing.expectEqualStrings("x", root.getAttributeValueRaw("Attr").?);
    try std.testing.expectEqualStrings("y", root.getAttributeValueRaw("attr").?);
    try std.testing.expect(root.getAttributeValueRaw("ATTR") == null);
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
    try std.testing.expectEqualStrings("1", root.getAttributeValueRaw("a").?);
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

test "strict invalid numeric entity in text fails on decoded access" {
    var parsed = try parseTestDoc("<r>&#x110000;</r>", .{ .mode = .strict });
    defer parsed.deinit();

    const text = parsed.doc.nodeAt(1).?.firstChild().?;
    try std.testing.expectEqualStrings("&#x110000;", text.valueRawSlice());
    try std.testing.expectError(error.InvalidNumericCharacterEntity, text.value(std.testing.allocator));
}

test "strict invalid numeric entity in attribute fails on decoded access" {
    var parsed = try parseTestDoc("<r a='&#x110000;'/>", .{ .mode = .strict });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1).?;
    try std.testing.expectEqualStrings("&#x110000;", root.getAttributeValueRaw("a").?);
    try std.testing.expectError(
        error.InvalidNumericCharacterEntity,
        root.getAttributeValue(std.testing.allocator, "a"),
    );
}

test "strict unterminated entity fails on decoded access" {
    var parsed = try parseTestDoc("<r>&amp</r>", .{ .mode = .strict });
    defer parsed.deinit();

    const text = parsed.doc.nodeAt(1).?.firstChild().?;
    try std.testing.expectEqualStrings("&amp", text.valueRawSlice());
    try std.testing.expectError(error.UnterminatedEntity, text.value(std.testing.allocator));
}

test "strict decoded access rejects unknown named entities when DTD expansion is disabled" {
    var parsed = try parseTestDoc("<r>&custom;</r>", .{ .mode = .strict });
    defer parsed.deinit();

    try std.testing.expectEqualStrings("&custom;", parsed.doc.nodeAt(1).?.firstChild().?.valueRawSlice());
    try std.testing.expectError(
        error.InvalidNumericCharacterEntity,
        parsed.doc.nodeAt(1).?.firstChild().?.value(std.testing.allocator),
    );
}

test "turbo invalid numeric entity stays literal in raw and decoded access" {
    var parsed = try parseTestDoc("<r a='&#x110000;'>&#x110000;</r>", .{ .mode = .turbo });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&#x110000;", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("&#x110000;", root.firstChild().?.valueRawSlice());

    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer std.testing.allocator.free(attr);
    try std.testing.expectEqualStrings("&#x110000;", attr);

    const text = try root.firstChild().?.value(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("&#x110000;", text);
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
    try std.testing.expectEqualStrings("1", doc.nodeAt(1).?.getAttributeValueRaw("x").?);
    try std.testing.expectEqualStrings("ok", doc.nodeAt(2).?.valueRawSlice());
}

test "u16 parse rejects input larger than index range" {
    if (common.IndexInt != u16) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    const opts: ParseOptions = .{};
    const Document = Types(opts).Document;
    var doc = Document.init(alloc);
    defer doc.deinit();

    const src = try alloc.alloc(u8, MaxInputLen + 1);
    defer alloc.free(src);
    @memset(src, 'a');
    src[0] = '<';
    src[1] = 'r';
    src[2] = '>';

    try std.testing.expectError(error.InputTooLarge, doc.parse(src, .{}));
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

test "streaming parser visits nodes in document order and exposes attributes" {
    const opts: ParseOptions = .{};
    const StreamingParserType = Types(opts).StreamingParser;
    const StreamingEventType = Types(opts).StreamingEvent;

    const Ctx = struct {
        names: std.ArrayList([]const u8),
        kinds: std.ArrayList(NodeType),
        depths: std.ArrayList(common.IndexInt),
        saw_root_attr: bool = false,
        saw_child_attr: bool = false,

        fn onNode(self: *@This(), node: StreamingEventType) bool {
            self.names.append(std.testing.allocator, node.nameSlice()) catch unreachable;
            self.kinds.append(std.testing.allocator, node.kind) catch unreachable;
            self.depths.append(std.testing.allocator, node.depth) catch unreachable;
            if (node.kind == .element and std.mem.eql(u8, node.nameSlice(), "r")) {
                self.saw_root_attr = std.mem.eql(u8, node.getAttributeValueRaw("id").?, "1");
            }
            if (node.kind == .element and std.mem.eql(u8, node.nameSlice(), "a")) {
                self.saw_child_attr = std.mem.eql(u8, node.getAttributeValueRaw("x").?, "y");
            }
            return true;
        }
    };

    var parser = StreamingParserType.init(std.testing.allocator);
    defer parser.deinit();

    var ctx: Ctx = .{
        .names = .empty,
        .kinds = .empty,
        .depths = .empty,
    };
    defer ctx.names.deinit(std.testing.allocator);
    defer ctx.kinds.deinit(std.testing.allocator);
    defer ctx.depths.deinit(std.testing.allocator);

    try parser.parse("<r id='1'><a x='y'>t</a><b/></r>", &ctx, Ctx.onNode);

    try std.testing.expectEqual(@as(usize, 4), ctx.kinds.items.len);
    try std.testing.expectEqualSlices(NodeType, &.{ .element, .element, .text, .element }, ctx.kinds.items);
    try std.testing.expectEqualStrings("r", ctx.names.items[0]);
    try std.testing.expectEqualStrings("a", ctx.names.items[1]);
    try std.testing.expectEqualStrings("", ctx.names.items[2]);
    try std.testing.expectEqualStrings("b", ctx.names.items[3]);
    try std.testing.expectEqualSlices(common.IndexInt, &.{ 0, 1, 2, 1 }, ctx.depths.items);
    try std.testing.expect(ctx.saw_root_attr);
    try std.testing.expect(ctx.saw_child_attr);
}

test "streaming parser can skip a subtree and expose adjacent text" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    const StreamingParserType = Types(opts).StreamingParser;
    const StreamingEventType = Types(opts).StreamingEvent;

    const Ctx = struct {
        names: std.ArrayList([]const u8),
        saw_skip_following_text: bool = false,
        saw_keep_leading_text: bool = false,

        fn onNode(self: *@This(), node: StreamingEventType) bool {
            self.names.append(std.testing.allocator, node.nameSlice()) catch unreachable;
            if (node.kind == .element and std.mem.eql(u8, node.nameSlice(), "skip")) {
                const following = node.followingTextRaw() catch unreachable;
                self.saw_skip_following_text = std.mem.eql(u8, following, "tail");
                return false;
            }
            if (node.kind == .element and std.mem.eql(u8, node.nameSlice(), "keep")) {
                self.saw_keep_leading_text = std.mem.eql(u8, node.leadingTextRaw(), "ok");
            }
            return true;
        }
    };

    var parser = StreamingParserType.init(std.testing.allocator);
    defer parser.deinit();

    var ctx: Ctx = .{ .names = .empty };
    defer ctx.names.deinit(std.testing.allocator);

    try parser.parse("<r><skip><x/></skip>tail<keep>ok</keep></r>", &ctx, Ctx.onNode);

    try std.testing.expectEqual(@as(usize, 5), ctx.names.items.len);
    try std.testing.expectEqualStrings("r", ctx.names.items[0]);
    try std.testing.expectEqualStrings("skip", ctx.names.items[1]);
    try std.testing.expectEqualStrings("", ctx.names.items[2]);
    try std.testing.expectEqualStrings("keep", ctx.names.items[3]);
    try std.testing.expectEqualStrings("", ctx.names.items[4]);
    try std.testing.expect(ctx.saw_skip_following_text);
    try std.testing.expect(ctx.saw_keep_leading_text);
}

test "streaming parser strict validation fails on mismatched close tags" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    const StreamingParserType = Types(opts).StreamingParser;
    const StreamingEventType = Types(opts).StreamingEvent;

    const Ctx = struct {
        fn onNode(_: *@This(), _: StreamingEventType) bool {
            return true;
        }
    };

    var parser = StreamingParserType.init(std.testing.allocator);
    defer parser.deinit();

    var ctx: Ctx = .{};
    try std.testing.expectError(error.InvalidClosingTagName, parser.parse("<r><a></r>", &ctx, Ctx.onNode));
}

test "streaming parser strict validation handles long close names" {
    const opts: ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    const StreamingParserType = Types(opts).StreamingParser;
    const StreamingEventType = Types(opts).StreamingEvent;

    const Ctx = struct {
        count: usize = 0,

        fn onNode(self: *@This(), _: StreamingEventType) bool {
            self.count += 1;
            return true;
        }
    };

    var parser = StreamingParserType.init(std.testing.allocator);
    defer parser.deinit();

    var ctx: Ctx = .{};
    try parser.parse("<rss><atom:link href='x'></atom:link><longername>t</longername></rss>", &ctx, Ctx.onNode);
    try std.testing.expectEqual(@as(usize, 4), ctx.count);
}

test "streaming parser accepts pointer callbacks" {
    const opts: ParseOptions = .{ .mode = .turbo };
    const StreamingParserType = Types(opts).StreamingParser;
    const StreamingEventType = Types(opts).StreamingEvent;

    const Ctx = struct {
        count: usize = 0,

        fn onNode(self: *@This(), node: *const StreamingEventType) bool {
            if (node.kind == .element) self.count += 1;
            return true;
        }
    };

    var parser = StreamingParserType.init(std.testing.allocator);
    defer parser.deinit();

    var ctx: Ctx = .{};
    try parser.parse("<r><a/><b/></r>", &ctx, Ctx.onNode);
    try std.testing.expectEqual(@as(usize, 3), ctx.count);
}

test "streaming parser turbo mode accepts unquoted attributes" {
    const opts: ParseOptions = .{ .mode = .turbo };
    const StreamingParserType = Types(opts).StreamingParser;
    const StreamingEventType = Types(opts).StreamingEvent;

    const Ctx = struct {
        saw_attr: bool = false,

        fn onNode(self: *@This(), node: StreamingEventType) bool {
            if (node.kind == .element and std.mem.eql(u8, node.nameSlice(), "r")) {
                self.saw_attr = std.mem.eql(u8, node.getAttributeValueRaw("a").?, "1");
            }
            return true;
        }
    };

    var parser = StreamingParserType.init(std.testing.allocator);
    defer parser.deinit();

    var ctx: Ctx = .{};
    try parser.parse("<r a=1/>", &ctx, Ctx.onNode);
    try std.testing.expect(ctx.saw_attr);
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

test "refAllDeclsRecursive: every zxml module compiles all declarations" {
    refAllDeclsRecursive(@This());
    refAllDeclsRecursive(document_mod);
    refAllDeclsRecursive(parser_mod);
    refAllDeclsRecursive(scanner_mod);
    refAllDeclsRecursive(tables_mod);
    refAllDeclsRecursive(entities_mod);
    refAllDeclsRecursive(streaming_mod);
}
