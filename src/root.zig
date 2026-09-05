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
pub const ParseOptions = document_mod.ParseOptions;
pub const ParseError = document_mod.ParseError;
pub const ParseDiagnostic = document_mod.ParseDiagnostic;
pub const InvalidIndex = document_mod.InvalidIndex;

pub fn Types(comptime options: ParseOptions) type {
    const doc_types = document_mod.Types(options);
    const stream_types = streaming_mod.Types(options);
    return struct {
        pub const IndexInt = doc_types.IndexInt;
        pub const Span = doc_types.Span;
        pub const RawAttribute = doc_types.RawAttribute;
        pub const RawAttributeIterator = doc_types.RawAttributeIterator;
        pub const Attribute = doc_types.Attribute;
        pub const AttributeIterator = doc_types.AttributeIterator;
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
    try doc.parse(buf);

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
    for (0..doc.nodes.items.len) |i| {
        if (doc.kindAt(@intCast(i)) == kind) n += 1;
    }
    return n;
}

fn findFirstKind(doc: anytype, kind: NodeType) ?std.meta.Child(@TypeOf(doc.nodeAt(0))) {
    for (0..doc.nodes.items.len) |i| {
        if (doc.kindAt(@intCast(i)) == kind) return doc.nodeAt(@intCast(i));
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

test "ParseOptions exposes zhtml-style type helpers and parse" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
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

test "decoded attribute and text helpers return ownership-aware slices" {
    var parsed = try parseTestDoc("<r a='&amp;&#x41;'>&lt;ok&gt;&#65;</r>", .{ .validate_well_formedness = true });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer attr.free(std.testing.allocator);
    try std.testing.expectEqualStrings("&A", attr.value);

    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    const decoded = try text.value(std.testing.allocator);
    defer decoded.free(std.testing.allocator);
    try std.testing.expectEqualStrings("<ok>A", decoded.value);
}

test "dtd entity expansion is opt-in and decodes internal entity references" {
    var parsed = try parseTestDoc("<!DOCTYPE r [<!ENTITY safe 'SAFE'>]><r a='&safe;'>&safe;</r>", .{
        .validate_well_formedness = true,
        .expand_dtd_entities = true,
    });
    defer parsed.deinit();

    const root = findFirstKind(&parsed.doc, .element) orelse return error.TestUnexpectedResult;
    const attr_raw = root.getAttributeValueRaw("a") orelse return error.TestUnexpectedResult;
    const child = root.firstChild() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&safe;", attr_raw);
    try std.testing.expectEqualStrings("&safe;", child.valueRawSlice());

    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer attr.free(std.testing.allocator);
    try std.testing.expectEqualStrings("SAFE", attr.value);

    const text = try child.value(std.testing.allocator);
    defer text.free(std.testing.allocator);
    try std.testing.expectEqualStrings("SAFE", text.value);
}

test "dtd entity expansion max value length is enforced" {
    var doc = initDoc(.{ .validate_well_formedness = true, .expand_dtd_entities = true, .max_entity_value_len = 4 });
    defer doc.deinit();

    var src = "<!DOCTYPE r [<!ENTITY big 'abcdef'>]><r>&big;</r>".*;
    try std.testing.expectError(ParseError.EntityValueTooLarge, doc.parse(&src));
}

test "document reuse clears opt-in dtd entity table" {
    var doc = initDoc(.{ .expand_dtd_entities = true });
    defer doc.deinit();

    var src1 = "<!DOCTYPE r [<!ENTITY safe 'SAFE'>]><r>&safe;</r>".*;
    try doc.parse(&src1);
    const first_root = findFirstKind(&doc, .element) orelse return error.TestUnexpectedResult;
    const first = try first_root.firstChild().?.value(std.testing.allocator);
    defer first.free(std.testing.allocator);
    try std.testing.expectEqualStrings("SAFE", first.value);

    var src2 = "<r>&safe;</r>".*;
    try doc.parse(&src2);
    const second_root = findFirstKind(&doc, .element) orelse return error.TestUnexpectedResult;
    const second = try second_root.firstChild().?.value(std.testing.allocator);
    defer second.free(std.testing.allocator);
    try std.testing.expectEqualStrings("&safe;", second.value);
}

test "decode disabled leaves literal entities in text and attributes" {
    var parsed = try parseTestDoc("<r a='&amp;'>&lt;ok&gt;</r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&amp;", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("&lt;ok&gt;", root.firstChild().?.valueRawSlice());
}

test "non destructive raw value access preserves source bytes" {
    var parsed = try parseTestDoc("<r a='&amp;'>&lt;ok&gt;</r>", .{ .non_destructive = true });
    defer parsed.deinit();

    const before = try std.testing.allocator.dupe(u8, parsed.buf);
    defer std.testing.allocator.free(before);

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    _ = root.getAttributeValueRaw("a").?;
    _ = root.firstChild().?.valueRawSlice();

    try std.testing.expectEqualStrings(before, parsed.buf);
}

test "decoded value preserves surrounding whitespace" {
    var parsed = try parseTestDoc("<r> a\n&amp;\t b  </r>", .{ .validate_well_formedness = true });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = root.firstChild() orelse return error.TestUnexpectedResult;
    const decoded = try text.value(std.testing.allocator);
    defer decoded.free(std.testing.allocator);
    try std.testing.expectEqualStrings(" a\n&\t b  ", decoded.value);
}

test "non destructive decoded helpers preserve source bytes" {
    var parsed = try parseTestDoc("<r a='&amp;'>&lt;ok&gt;</r>", .{ .validate_well_formedness = true, .non_destructive = true });
    defer parsed.deinit();

    const before = try std.testing.allocator.dupe(u8, parsed.buf);
    defer std.testing.allocator.free(before);

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer attr.free(std.testing.allocator);
    try std.testing.expectEqualStrings("&", attr.value);

    const text = try root.firstChild().?.value(std.testing.allocator);
    defer text.free(std.testing.allocator);
    try std.testing.expectEqualStrings("<ok>", text.value);
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
    var parsed = try parseTestDoc("<r>a&amp;<b/>c&#33;</r>", .{ .validate_well_formedness = true });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const text = try root.innerText(std.testing.allocator);
    defer text.free(std.testing.allocator);
    try std.testing.expectEqualStrings("a&c!", text.value);
}

test "CDATA stays literal in value and contributes to innerText" {
    var parsed = try parseTestDoc("<r>a&amp;<![CDATA[&bogus;<x>]]>c</r>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    const cdata = findFirstKind(&parsed.doc, .cdata) orelse return error.TestUnexpectedResult;
    const cdata_value = try cdata.value(std.testing.allocator);
    defer cdata_value.free(std.testing.allocator);
    try std.testing.expectEqualStrings("&bogus;<x>", cdata_value.value);

    const text = try root.innerText(std.testing.allocator);
    defer text.free(std.testing.allocator);
    try std.testing.expectEqualStrings("a&&bogus;<x>c", text.value);
    try std.testing.expect(root.innerTextRaw() == null);
}

test "non-text node value does not decode entity-looking content" {
    var parsed = try parseTestDoc("<r><!-- &bogus; --></r>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    const comment = findFirstKind(&parsed.doc, .comment) orelse return error.TestUnexpectedResult;
    const value = try comment.value(std.testing.allocator);
    defer value.free(std.testing.allocator);
    try std.testing.expectEqualStrings(" &bogus; ", value.value);
}

test "innerText helpers return empty content for textless elements" {
    var parsed = try parseTestDoc("<r><a/></r>", .{ .validate_well_formedness = true });
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("", root.innerTextRaw().?);
    const text = try root.innerText(std.testing.allocator);
    defer text.free(std.testing.allocator);
    try std.testing.expectEqualStrings("", text.value);
}

test "misc nodes enabled parses declaration nodes" {
    var parsed = try parseTestDoc("<?xml version='1.0'?><root/>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .declaration) != null);
}

test "misc nodes enabled parses comment nodes" {
    var parsed = try parseTestDoc("<root><!--c--></root>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .comment) != null);
}

test "misc nodes enabled parses cdata nodes" {
    var parsed = try parseTestDoc("<root><![CDATA[x]]></root>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .cdata) != null);
}

test "misc nodes enabled parses processing instructions" {
    var parsed = try parseTestDoc("<root><?p q?></root>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .pi) != null);
}

test "misc nodes enabled parses doctypes" {
    var parsed = try parseTestDoc("<!DOCTYPE root [<!ELEMENT root ANY>]><root/>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    try std.testing.expect(findFirstKind(&parsed.doc, .doctype) != null);
}

test "misc nodes disabled omits declaration comment cdata pi and doctype" {
    var parsed = try parseTestDoc("<?xml version='1.0'?><!DOCTYPE root [<!ELEMENT root ANY>]><root><!--c--><![CDATA[x]]><?p q?></root>", .{
        .validate_well_formedness = true,
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
    var parsed = try parseTestDoc("<?xml version='1.0' encoding='utf-8'?><root/>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    const decl = findFirstKind(&parsed.doc, .declaration) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("xml", decl.nameSlice());
    try std.testing.expect(std.mem.indexOf(u8, decl.valueRawSlice(), "version='1.0'") != null);
}

test "processing instruction stores target and value" {
    var parsed = try parseTestDoc("<root><?build target='bench'?></root>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    const pi = findFirstKind(&parsed.doc, .pi) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("build", pi.nameSlice());
    try std.testing.expectEqualStrings("target='bench'", pi.valueRawSlice());
}

test "comment nodes expose their value slice" {
    var parsed = try parseTestDoc("<root><!--hello--></root>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    const comment = findFirstKind(&parsed.doc, .comment) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("hello", comment.valueRawSlice());
}

test "cdata nodes expose their value slice" {
    var parsed = try parseTestDoc("<root><![CDATA[a < b && c]]></root>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    const cdata = findFirstKind(&parsed.doc, .cdata) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("a < b && c", cdata.valueRawSlice());
}

test "doctype preserves internal subset text" {
    var parsed = try parseTestDoc("<!DOCTYPE root [<!ELEMENT root ANY><!ATTLIST root id CDATA #IMPLIED>]><root/>", .{ .validate_well_formedness = true, .include_misc_nodes = true });
    defer parsed.deinit();

    const doctype = findFirstKind(&parsed.doc, .doctype) orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, doctype.valueRawSlice(), "<!ELEMENT root ANY>") != null);
    try std.testing.expect(std.mem.indexOf(u8, doctype.valueRawSlice(), "<!ATTLIST root") != null);
}

test "permissive mismatched close tag recovers by name" {
    var parsed = try parseTestDoc("<a><b></a>", .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.doc.nodes.items.len);
    try std.testing.expectEqualStrings("a", parsed.doc.nodeAt(1).?.nameSlice());
    try std.testing.expectEqualStrings("b", parsed.doc.nodeAt(2).?.nameSlice());
}

test "validated mismatched close tag validation fails" {
    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();

    var src = "<a><b></a>".*;
    try std.testing.expectError(ParseError.InvalidClosingTagName, doc.parse(&src));
}

test "permissive mode tolerates EOF with open elements" {
    var parsed = try parseTestDoc("<a><b>", .{});
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 3), parsed.doc.nodes.items.len);
    try std.testing.expectEqualStrings("a", parsed.doc.nodeAt(1).?.nameSlice());
    try std.testing.expectEqualStrings("b", parsed.doc.nodeAt(2).?.nameSlice());
}

test "validated mode requires balanced open elements" {
    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();

    var src = "<a><b>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src));
}

test "permissive mode builds dom by default" {
    var parsed = try parseTestDoc("<root><a>v</a><b x='1'/></root>", .{
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

    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();
    try doc.parse(xml.items);

    const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("v0", root.getAttributeValueRaw("a0").?);
    try std.testing.expectEqualStrings("v63", root.getAttributeValueRaw("a63").?);
    var attrs = root.attributes();
    var attr_count: usize = 0;
    while (attrs.next()) |_| attr_count += 1;
    try std.testing.expectEqual(@as(usize, 64), attr_count);
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

test "validated attribute grammar covers XML whitespace and quoted value boundaries" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
    var doc = initDoc(opts);
    defer doc.deinit();

    const valid = [_]struct { source: []const u8, b: ?[]const u8 = null }{
        .{ .source = "<r a='1'/>" },
        .{ .source = "<r\ta='1'/>" },
        .{ .source = "<r\na='1'/>" },
        .{ .source = "<r\ra='1'/>" },
        .{ .source = "<r  a='1'/>" },
        .{ .source = "<r a \t=\r\n '1'/>" },
        .{ .source = "<r a='1'\tb='2'/>", .b = "2" },
        .{ .source = "<r a='1'\nb='2'/>", .b = "2" },
        .{ .source = "<r a='1'\rb='2'/>", .b = "2" },
        .{ .source = "<r a='1'   b='2'/>", .b = "2" },
        .{ .source = "<r a='1' \n\t b = \"2\"/>", .b = "2" },
    };
    for (valid) |case| {
        try doc.parse(case.source);
        const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings("1", root.getAttributeValueRaw("a") orelse return error.TestUnexpectedResult);
        if (case.b) |expected| try std.testing.expectEqualStrings(expected, root.getAttributeValueRaw("b") orelse return error.TestUnexpectedResult);
    }

    var source = std.ArrayList(u8).empty;
    defer source.deinit(std.testing.allocator);
    const lengths = [_]usize{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15, 16, 31, 32, 33, 63, 64, 65, 127, 128, 129 };
    for (lengths) |len| {
        inline for (.{ '\'', '"' }) |quote| {
            source.clearRetainingCapacity();
            try source.appendSlice(std.testing.allocator, "<r a=");
            try source.append(std.testing.allocator, quote);
            for (0..len) |_| try source.append(std.testing.allocator, 'x');
            try source.append(std.testing.allocator, quote);
            try source.appendSlice(std.testing.allocator, "/>");
            try doc.parse(source.items);
            const root = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
            const raw = root.getAttributeValueRaw("a") orelse return error.TestUnexpectedResult;
            try std.testing.expectEqual(len, raw.len);
            for (raw) |byte| try std.testing.expectEqual(@as(u8, 'x'), byte);
        }
    }

    const invalid = [_]struct { source: []const u8, err: ParseError }{
        .{ .source = "<r a '1'/>", .err = error.ExpectedEq },
        .{ .source = "<r a=1/>", .err = error.ExpectedQuote },
        .{ .source = "<r a='x' b/>", .err = error.ExpectedEq },
        .{ .source = "<r a='x' b =/>", .err = error.ExpectedQuote },
        .{ .source = "<r a='x' b='y'c='z'/>", .err = error.ExpectedAttributeName },
        .{ .source = "<r a='x<y'/>", .err = error.InvalidAttributeValue },
        .{ .source = "<r a='&amp'/>", .err = error.UnterminatedEntity },
        .{ .source = "<r a='&bogus;'/>", .err = error.InvalidNumericCharacterEntity },
    };
    for (invalid) |case| try std.testing.expectError(case.err, doc.parse(case.source));

    // A failure must not leave attribute spans or parser scratch visible to the next parse.
    try doc.parse("<ok a='fresh' b='state'/>");
    const recovered = doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("fresh", recovered.getAttributeValueRaw("a") orelse return error.TestUnexpectedResult);
    try std.testing.expectEqualStrings("state", recovered.getAttributeValueRaw("b") orelse return error.TestUnexpectedResult);
}

test "validated duplicate attributes cover short long Unicode and dispatch boundaries" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
    var doc = initDoc(opts);
    defer doc.deinit();

    const duplicate_pairs = [_][]const u8{
        "<r a='1' a='2'/>",
        "<r z='1' z='2'></r>",
        "<r abcdefghi='1' abcdefghi='2'/>",
        "<r ns:item='1' ns:item='2'/>",
        "<r é='1' é='2'/>",
    };
    for (duplicate_pairs) |source_text| try std.testing.expectError(error.DuplicateAttribute, doc.parse(source_text));

    const distinct_pairs = [_][]const u8{
        "<r A='1' a='2'/>",
        "<r abcdefghi='1' abcdefghj='2'/>",
        "<r ns:item='1' ns:Item='2'/>",
        "<r é='1' É='2'/>",
    };
    for (distinct_pairs) |source_text| try doc.parse(source_text);

    var many = std.ArrayList(u8).empty;
    defer many.deinit(std.testing.allocator);
    const counts = [_]usize{ 3, 31, 32, 33, 95, 96, 97 };
    for (counts) |count| {
        many.clearRetainingCapacity();
        try many.appendSlice(std.testing.allocator, "<r");
        for (0..count) |index| try many.print(std.testing.allocator, " a{d}='{d}'", .{ index, index });
        try many.appendSlice(std.testing.allocator, "/>");
        try doc.parse(many.items);

        many.items.len -= 2;
        const duplicate_index = count / 2;
        try many.print(std.testing.allocator, " a{d}='duplicate'/>", .{duplicate_index});
        try std.testing.expectError(error.DuplicateAttribute, doc.parse(many.items));
    }
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

test "validated unquoted attributes fail" {
    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();

    var src = "<r a=1/>".*;
    try std.testing.expectError(ParseError.ExpectedQuote, doc.parse(&src));
}

test "permissive unquoted attributes parse" {
    var parsed = try parseTestDoc("<r a=1/>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("1", root.getAttributeValueRaw("a").?);
    var attrs = root.attributes();
    const attr = attrs.next() orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("a", attr.nameSlice());
    try std.testing.expectEqualStrings("1", attr.valueRawSlice());
    try std.testing.expect(attrs.next() == null);
}

test "validated unterminated quoted attribute fails" {
    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();

    var src = "<r a='x></r>".*;
    try std.testing.expectError(ParseError.ExpectedQuote, doc.parse(&src));
}

test "validated unterminated comment fails" {
    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();

    var src = "<r><!--x</r>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src));
}

test "validated unterminated cdata fails" {
    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();

    var src = "<r><![CDATA[x</r>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src));
}

test "validated unterminated processing instruction fails" {
    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();

    var src = "<r><?build x='1'</r>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src));
}

test "validated unterminated doctype fails" {
    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();

    var src = "<!DOCTYPE root [<!ELEMENT root ANY><root/>".*;
    try std.testing.expectError(ParseError.UnexpectedEndOfData, doc.parse(&src));
}

test "validated rejects malformed and XML-invalid references during parse" {
    const invalid = [_][]const u8{
        "<r>&#X41;</r>",
        "<r>&#0;</r>",
        "<r>&#xD800;</r>",
        "<r>&#x110000;</r>",
        "<r>&;</r>",
        "<r>&1x;</r>",
        "<r>&amp</r>",
        "<r a='&#0;' />",
        "<r a='&#X41;' />",
        "<r a='&1x;' />",
        "<r a='&amp' />",
        "<r a='a&b' />",
    };

    inline for (invalid) |source| {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            if (std.mem.indexOf(u8, source, ";") == null) error.UnterminatedEntity else error.InvalidNumericCharacterEntity,
            doc.parse(source),
        );
    }

    var parsed = try parseTestDoc("<r a='&amp;&#65;&#x42;'>&lt;&#9;&#xA;&#x10FFFF;&#x00010FFFF;</r>", .{
        .validate_well_formedness = true,
    });
    defer parsed.deinit();
}

test "validated enforces declared parsed general entities" {
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(error.InvalidNumericCharacterEntity, doc.parse("<r>&custom;</r>"));
    }
    {
        var parsed = try parseTestDoc("<!DOCTYPE r [<!ENTITY custom 'x'>]><r>&custom;</r>", .{
            .validate_well_formedness = true,
        });
        defer parsed.deinit();
        const root = findFirstKind(&parsed.doc, .element) orelse return error.TestUnexpectedResult;
        const text = root.firstChild() orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings("&custom;", text.valueRawSlice());
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        const source = "<!DOCTYPE r [<!NOTATION n SYSTEM 'urn:n'><!ENTITY custom SYSTEM 'urn:x' NDATA n>]><r>&custom;</r>";
        try std.testing.expectError(error.InvalidNumericCharacterEntity, doc.parse(source));
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        const source = "<!DOCTYPE r [<!NOTATION n SYSTEM 'urn:n'><!ENTITY custom SYSTEM 'urn:x' NDATA n><!ENTITY custom 'later'>]><r>&custom;</r>";
        try std.testing.expectError(error.InvalidNumericCharacterEntity, doc.parse(source));
    }
    {
        var parsed = try parseTestDoc("<!DOCTYPE r [<!ENTITY custom 'first'><!NOTATION n SYSTEM 'urn:n'><!ENTITY custom SYSTEM 'urn:x' NDATA n>]><r>&custom;</r>", .{
            .validate_well_formedness = true,
        });
        defer parsed.deinit();
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            error.InvalidNumericCharacterEntity,
            doc.parse("<!DOCTYPE r><r a='&missing;'/>"),
        );
        try std.testing.expectError(
            error.UnterminatedEntity,
            doc.parse("<!DOCTYPE r><r a='&amp'/>"),
        );
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try doc.parse("<!DOCTYPE r SYSTEM 'urn:external'><r>&external;</r>");
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        const source = "<?xml version='1.0' standalone='yes'?><!DOCTYPE r SYSTEM 'urn:external'><r>&external;</r>";
        try std.testing.expectError(error.InvalidNumericCharacterEntity, doc.parse(source));
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        const source = "<!DOCTYPE r [<!ENTITY external SYSTEM 'urn:x'>]><r a='&external;'/>";
        try std.testing.expectError(error.InvalidAttributeValue, doc.parse(source));
    }
    {
        var parsed = try parseTestDoc("<!DOCTYPE r [<!ENTITY external SYSTEM 'urn:x'>]><r>&external;</r>", .{
            .validate_well_formedness = true,
        });
        defer parsed.deinit();
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        const source = "<!DOCTYPE r SYSTEM 'urn:subset' [<!NOTATION n SYSTEM 'urn:n'><!ENTITY raw SYSTEM 'urn:x' NDATA n>]><r>&raw;</r>";
        try std.testing.expectError(error.InvalidNumericCharacterEntity, doc.parse(source));
    }
}

test "validated reuses validated entity references across repeated DOM attributes" {
    {
        var parsed = try parseTestDoc(
            "<!DOCTYPE r [<!ENTITY a 'ok'>]><r x='&a;' y='&a;' z='&a;'/>",
            .{
                .validate_well_formedness = true,
            },
        );
        defer parsed.deinit();
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            error.InvalidNumericCharacterEntity,
            doc.parse("<!DOCTYPE r [<!ENTITY a 'ok'>]><r x='&a;' y='&a;' z='&missing;'/>"),
        );
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            error.InvalidAttributeValue,
            doc.parse("<!DOCTYPE r [<!ENTITY a 'ok'><!ENTITY e SYSTEM 'urn:x'>]><r x='&a;' y='&a;' z='&e;'/>"),
        );
    }
}

test "validated repeated custom entity fast path preserves later validation" {
    {
        var parsed = try parseTestDoc(
            "<!DOCTYPE r [<!ENTITY a 'ok'>]><r>&a;&a;&a;&a;&a;&a;&a;&a;</r>",
            .{
                .validate_well_formedness = true,
            },
        );
        defer parsed.deinit();
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            error.InvalidNumericCharacterEntity,
            doc.parse("<!DOCTYPE r [<!ENTITY a 'ok'>]><r>&a;&a;&a;&a;&#0;</r>"),
        );
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            error.InvalidNumericCharacterEntity,
            doc.parse("<!DOCTYPE r [<!ENTITY a 'ok'>]><r>&a;&a;&a;&missing;</r>"),
        );
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            error.UnterminatedEntity,
            doc.parse("<!DOCTYPE r [<!ENTITY a 'ok'>]><r>&a;&a;&a;&a</r>"),
        );
    }
}

test "validated validates used entity replacement graphs" {
    const invalid_entity = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY a '&missing;'>]><r>&a;</r>",
        "<!DOCTYPE r [<!NOTATION n SYSTEM 'n'><!ENTITY e SYSTEM 'x' NDATA n><!ENTITY a '&e;'>]><r>&a;</r>",
        "<!DOCTYPE r [<!ENTITY a '&#38;missing;'>]><r>&a;</r>",
    };
    inline for (invalid_entity) |source| {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(error.InvalidNumericCharacterEntity, doc.parse(source));
    }

    const recursive = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY a '&a;'>]><r>&a;</r>",
        "<!DOCTYPE r [<!ENTITY a '&b;'><!ENTITY b '&a;'>]><r>&a;</r>",
    };
    inline for (recursive) |source| {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(error.RecursiveEntity, doc.parse(source));
    }

    const invalid_attribute = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY a '&e;'><!ENTITY e SYSTEM 'x'>]><r x='&a;'/>",
        "<!DOCTYPE r [<!ENTITY a '<'>]><r x='&a;'/>",
        "<!DOCTYPE r [<!ENTITY a '&b;'><!ENTITY b '<'>]><r x='&a;'/>",
        "<!DOCTYPE r [<!ENTITY a '&#60;'>]><r x='&a;'/>",
        "<!DOCTYPE r [<!ENTITY a '&#38;e;'><!ENTITY e SYSTEM 'x'>]><r x='&a;'/>",
    };
    inline for (invalid_attribute) |source| {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(error.InvalidAttributeValue, doc.parse(source));
    }

    const valid = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY a '&b;'><!ENTITY b 'ok'>]><r>&a;</r>",
        "<!DOCTYPE r [<!ENTITY a '&lt;'>]><r x='&a;'/>",
        "<!DOCTYPE r [<!ENTITY a '&#38;lt;'>]><r x='&a;'/>",
        "<!DOCTYPE r [<!ENTITY a '&amp;e;'><!ENTITY e SYSTEM 'x'>]><r x='&a;'/>",
        "<!DOCTYPE r [<!ENTITY a '&a;'>]><r/>",
    };
    inline for (valid) |source| {
        var parsed = try parseTestDoc(source, .{
            .validate_well_formedness = true,
        });
        defer parsed.deinit();
    }
}

test "validated validates internal parameter entity replacement text" {
    const invalid = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY % p 'x'>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % p '<!ELEMENT>'>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % q 'x'><!ENTITY % p '&#37;q;'>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % p '<![INCLUDE[<!ELEMENT r EMPTY>]]>'>%p;]><r/>",
    };
    inline for (invalid) |source| {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(error.InvalidDoctype, doc.parse(source));
    }

    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            error.RecursiveEntity,
            doc.parse("<!DOCTYPE r [<!ENTITY % p '&#37;p;'>%p;]><r/>"),
        );
    }

    const valid = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY % p '   '>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % p '<!ELEMENT r EMPTY>'>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % p '&#60;!ELEMENT r EMPTY>'>%p;]><r/>",
        "<!DOCTYPE r [<!ENTITY % q '<!ELEMENT r EMPTY>'><!ENTITY % p '&#37;q;'>%p;]><r/>",
        "<!DOCTYPE r [%unknown;]><r/>",
        "<!DOCTYPE r [<!ENTITY % p SYSTEM 'urn:external'>%p;]><r/>",
    };
    inline for (valid) |source| {
        var parsed = try parseTestDoc(source, .{
            .validate_well_formedness = true,
        });
        defer parsed.deinit();
    }
}

test "validated applies entity constraints to declarations from parameter entities" {
    const invalid_entity = [_][]const u8{
        "<!DOCTYPE r [<!NOTATION n SYSTEM 'n'><!ENTITY % p \"<!ENTITY e SYSTEM 'x' NDATA n>\">%p;]><r>&e;</r>",
    };
    inline for (invalid_entity) |source| {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(error.InvalidNumericCharacterEntity, doc.parse(source));
    }

    const invalid_attribute = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY % p \"<!ENTITY e SYSTEM 'x'>\">%p;]><r a='&e;'/>",
        "<!DOCTYPE r [<!ENTITY % p \"<!ENTITY e '&#60;'>\">%p;]><r a='&e;'/>",
    };
    inline for (invalid_attribute) |source| {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(error.InvalidAttributeValue, doc.parse(source));
    }

    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            error.RecursiveEntity,
            doc.parse("<!DOCTYPE r [<!ENTITY % p \"<!ENTITY e '&e;'>\">%p;]><r>&e;</r>"),
        );
    }
    {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(
            error.InvalidDoctype,
            doc.parse("<?xml version='1.0' standalone='yes'?><!DOCTYPE r [%unknown;]><r/>"),
        );
    }

    var parsed = try parseTestDoc(
        "<!DOCTYPE r [<!ENTITY % p \"<!ENTITY e 'ok'>\">%p;]><r>&e;</r>",
        .{
            .validate_well_formedness = true,
        },
    );
    defer parsed.deinit();
}

test "validated parameter entity inclusion is iterative for deep chains" {
    var source = std.ArrayList(u8).empty;
    defer source.deinit(std.testing.allocator);
    try source.appendSlice(std.testing.allocator, "<!DOCTYPE r [");
    const depth: usize = 512;
    for (0..depth - 1) |i| {
        try source.print(std.testing.allocator, "<!ENTITY % p{d} '&#37;p{d};'>", .{ i, i + 1 });
    }
    try source.print(std.testing.allocator, "<!ENTITY % p{d} '&#60;!ELEMENT r EMPTY>'>%p0;]><r/>", .{depth - 1});

    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();
    try doc.parse(source.items);
}

test "validated validates DTD attribute default entity constraints in declaration order" {
    const undeclared_or_forward = [_][]const u8{
        "<!DOCTYPE r [<!ATTLIST r a CDATA '&e;'><!ENTITY e 'x'>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA '&e;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY e '&x;'><!ATTLIST r a CDATA '&e;'><!ENTITY x 'v'>]><r/>",
        "<?xml version='1.0' standalone='yes'?><!DOCTYPE r SYSTEM 'urn:missing' [<!ATTLIST r a CDATA '&e;'>]><r/>",
    };
    inline for (undeclared_or_forward) |source| {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(error.InvalidNumericCharacterEntity, doc.parse(source));
    }

    const invalid_attribute = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY e SYSTEM 'x'><!ATTLIST r a CDATA '&e;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY e '<'><!ATTLIST r a CDATA '&e;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY e '&x;'><!ENTITY x SYSTEM 'x'><!ATTLIST r a CDATA '&e;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY e '&#60;'><!ATTLIST r a CDATA #FIXED '&e;'>]><r/>",
    };
    inline for (invalid_attribute) |source| {
        var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
        defer doc.deinit();
        try std.testing.expectError(error.InvalidAttributeValue, doc.parse(source));
    }

    const valid = [_][]const u8{
        "<!DOCTYPE r [<!ENTITY e 'x'><!ATTLIST r a CDATA '&e;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY x 'v'><!ENTITY e '&x;'><!ATTLIST r a CDATA '&e;'>]><r/>",
        "<!DOCTYPE r SYSTEM 'urn:missing' [<!ATTLIST r a CDATA '&external;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY e '&lt;'><!ATTLIST r a CDATA #FIXED '&e;'>]><r/>",
    };
    inline for (valid) |source| {
        var parsed = try parseTestDoc(source, .{
            .validate_well_formedness = true,
        });
        defer parsed.deinit();
    }
}

test "validated entity graph validation is iterative for deep chains" {
    var source = std.ArrayList(u8).empty;
    defer source.deinit(std.testing.allocator);
    try source.appendSlice(std.testing.allocator, "<!DOCTYPE r [<!ENTITY e0 'ok'>");
    const depth: usize = 1024;
    var i: usize = 1;
    while (i < depth) : (i += 1) {
        try source.print(std.testing.allocator, "<!ENTITY e{d} '&e{d};'>", .{ i, i - 1 });
    }
    try source.print(std.testing.allocator, "]><r>&e{d};</r>", .{depth - 1});

    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();
    try doc.parse(source.items);
}

test "permissive invalid numeric entity stays literal in raw and decoded access" {
    var parsed = try parseTestDoc("<r a='&#x110000;'>&#x110000;</r>", .{});
    defer parsed.deinit();

    const root = parsed.doc.nodeAt(1) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("&#x110000;", root.getAttributeValueRaw("a").?);
    try std.testing.expectEqualStrings("&#x110000;", root.firstChild().?.valueRawSlice());

    const attr = try root.getAttributeValue(std.testing.allocator, "a") orelse return error.TestUnexpectedResult;
    defer attr.free(std.testing.allocator);
    try std.testing.expectEqualStrings("&#x110000;", attr.value);

    const text = try root.firstChild().?.value(std.testing.allocator);
    defer text.free(std.testing.allocator);
    try std.testing.expectEqualStrings("&#x110000;", text.value);
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
    try doc.parse(&src1);
    try std.testing.expectEqual(@as(usize, 3), doc.nodes.items.len);

    var src2 = "<root x='1'>ok</root>".*;
    try doc.parse(&src2);
    try std.testing.expectEqual(@as(usize, 3), doc.nodes.items.len);
    try std.testing.expectEqualStrings("root", doc.nodeAt(1).?.nameSlice());
    try std.testing.expectEqualStrings("1", doc.nodeAt(1).?.getAttributeValueRaw("x").?);
    try std.testing.expectEqualStrings("ok", doc.nodeAt(2).?.valueRawSlice());
}

test "u16 parse accepts input exactly at the index range boundary" {
    if (common.IndexInt != u16) return error.SkipZigTest;

    const alloc = std.testing.allocator;
    const opts: ParseOptions = .{ .validate_well_formedness = true, .non_destructive = true };
    const Document = Types(opts).Document;
    var doc = Document.init(alloc);
    defer doc.deinit();

    const src = try alloc.alloc(u8, MaxInputLen);
    defer alloc.free(src);
    @memset(src, ' ');
    @memcpy(src[0..3], "<r>");
    @memcpy(src[src.len - 4 ..], "</r>");

    try doc.parse(src);
    try std.testing.expectEqual(@as(usize, 2), doc.nodes.items.len);
    try std.testing.expectEqual(@as(common.IndexInt, MaxInputLen), @as(common.IndexInt, @intCast(src.len)));
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

    try std.testing.expectError(error.InputTooLarge, doc.parse(src));
}

test "validated deep balanced close tags" {
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

    var doc = initDoc(.{ .validate_well_formedness = true, .non_destructive = true });
    defer doc.deinit();
    try doc.parse(xml.items);

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
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
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

test "streaming parser validated validation fails on mismatched close tags" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
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

test "streaming parser validated validation handles long close names" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
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
    const opts: ParseOptions = .{};
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

test "streaming parser permissive mode accepts unquoted attributes" {
    const opts: ParseOptions = .{};
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

test "validated enforces document-level well-formedness" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
    var doc = initDoc(opts);
    defer doc.deinit();

    try std.testing.expectError(error.ExpectedDocumentElement, doc.parse(""));
    try std.testing.expectError(error.ExpectedDocumentElement, doc.parse("<!--only misc-->"));
    try std.testing.expectError(error.MultipleDocumentElements, doc.parse("<a/><b/>"));
    try std.testing.expectError(error.InvalidDocumentContent, doc.parse("text<a/>"));
    try std.testing.expectError(error.InvalidDocumentContent, doc.parse("<a/>text"));
    try std.testing.expectError(error.InvalidDocumentContent, doc.parse("<![CDATA[x]]><a/>"));
    try std.testing.expectError(error.InvalidDoctype, doc.parse("<!DOCTYPE a><!DOCTYPE a><a/>"));
    try std.testing.expectError(error.InvalidDoctype, doc.parse("<a/><!DOCTYPE a>"));
    try std.testing.expectError(error.InvalidDoctype, doc.parse("<a><!DOCTYPE a></a>"));
    try std.testing.expectError(error.InvalidDeclaration, doc.parse(" <?xml version='1.0'?><a/>"));
    try std.testing.expectError(error.InvalidDeclaration, doc.parse("<?pi x?><?xml version='1.0'?><a/>"));

    try doc.parse("<?xml version='1.0'?><!--x--><!DOCTYPE a><a><![CDATA[x]]></a><?pi y?>");
}

test "validated validates processing instruction separators" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
    var doc = initDoc(opts);
    defer doc.deinit();

    const invalid = [_][]const u8{
        "<?pi=data?><r/>",
        "<?pi/data?><r/>",
        "<r><?pi:data/x?></r>",
    };
    inline for (invalid) |source| {
        try std.testing.expectError(error.ExpectedGt, doc.parse(source));
    }

    try doc.parse("<?pi?><r/>");
    try doc.parse("<?pi data?><r/>");
}

test "validated two-attribute duplicate pair checks exact names" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
    var doc = initDoc(opts);
    defer doc.deinit();

    try doc.parse("<r id='1' kind='2'/>");
    try doc.parse("<r aa='1' bb='2'/>");
    try doc.parse("<r a='1' b='2'/>");
    try doc.parse("<r é='1' É='2'/>");
    try std.testing.expectError(error.DuplicateAttribute, doc.parse("<r id='1' id='2'/>"));
    try std.testing.expectError(error.DuplicateAttribute, doc.parse("<r long_name='1' long_name='2'/>"));
    try std.testing.expectError(error.DuplicateAttribute, doc.parse("<r é='1' é='2'/>"));
}

test "validated rejects duplicate attribute names" {
    const validated_opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
    var validated_doc = initDoc(validated_opts);
    defer validated_doc.deinit();
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse("<r a='1' a='2'/>"));
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse("<r><x a='1' b='2' a='3'/></r>"));

    const duplicate_pair_self = "<r a='1' a='2'/>";
    const self_diag = validated_doc.parseDiagnostic(duplicate_pair_self) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(error.DuplicateAttribute, self_diag.err);
    try std.testing.expectEqual(@as(usize, 9), self_diag.offset);

    const duplicate_pair_open = "<r a='1' a='2'></r>";
    const open_diag = validated_doc.parseDiagnostic(duplicate_pair_open) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(error.DuplicateAttribute, open_diag.err);
    try std.testing.expectEqual(@as(usize, 9), open_diag.offset);
    // Distinct names sharing the lightweight uniqueness bucket must fall back
    // to exact comparisons rather than false-positive as duplicates.
    try validated_doc.parse("<r h='1' ab='2' z='3'/>");

    var many = std.ArrayList(u8).empty;
    defer many.deinit(std.testing.allocator);
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..65) |index| try many.print(std.testing.allocator, " a{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, "/>");
    try validated_doc.parse(many.items);
    many.items.len -= 2;
    try many.appendSlice(std.testing.allocator, " a63='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    // Exercise the full 256-slot exact table, including a duplicate at its
    // saturation boundary, and the >256 exact fallback.
    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..256) |index| try many.print(std.testing.allocator, " b{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, "/>");
    try validated_doc.parse(many.items);

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..255) |index| try many.print(std.testing.allocator, " c{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " c127='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..256) |index| try many.print(std.testing.allocator, " d{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " d127='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    // Exercise the widened 512-slot exact table and preserve exact fallback
    // behavior immediately beyond its saturation boundary.
    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..512) |index| try many.print(std.testing.allocator, " e{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, "/>");
    try validated_doc.parse(many.items);

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..511) |index| try many.print(std.testing.allocator, " f{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " f255='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..512) |index| try many.print(std.testing.allocator, " g{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " g255='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    // Exercise the widened 1024-slot exact table and its >1024 fallback.
    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..1024) |index| try many.print(std.testing.allocator, " h{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, "/>");
    try validated_doc.parse(many.items);

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..1023) |index| try many.print(std.testing.allocator, " i{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " i511='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..1024) |index| try many.print(std.testing.allocator, " j{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " j511='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    // Exercise the widened 2048-slot exact table and its >2048 fallback.
    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..2048) |index| try many.print(std.testing.allocator, " k{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, "/>");
    try validated_doc.parse(many.items);

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..2047) |index| try many.print(std.testing.allocator, " l{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " l1023='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..2048) |index| try many.print(std.testing.allocator, " m{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " m1023='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    // Exercise the widened 4096-slot exact table and its >4096 fallback.
    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..4096) |index| try many.print(std.testing.allocator, " n{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, "/>");
    try validated_doc.parse(many.items);

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..4095) |index| try many.print(std.testing.allocator, " o{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " o2047='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    many.clearRetainingCapacity();
    try many.appendSlice(std.testing.allocator, "<r");
    for (0..4096) |index| try many.print(std.testing.allocator, " p{d}='{d}'", .{ index, index });
    try many.appendSlice(std.testing.allocator, " p2047='duplicate'/>");
    try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));

    // Exercise the partitioned >4096 path at its major boundaries. The
    // boundary number is the unique attribute count; the final attribute
    // duplicates the first. Compact fixed-width names keep 4097 and 8193
    // representable when IndexInt is u16.
    const overflow_unique_counts = [_]usize{ 4097, 8193, 32769, 65537, 131072 };
    const base36 = "0123456789abcdefghijklmnopqrstuvwxyz";
    for (overflow_unique_counts) |unique_count| {
        const name_width: usize = if (unique_count <= 26 * 36 * 36) 3 else 4;
        const generated_len = 2 + unique_count * (name_width + 4) + (name_width + 6);
        if (generated_len > MaxInputLen) continue;

        many.clearRetainingCapacity();
        try many.appendSlice(std.testing.allocator, "<r");
        for (0..unique_count) |index| {
            var name: [4]u8 = undefined;
            var quotient = index;
            var pos = name_width;
            while (pos > 1) {
                pos -= 1;
                name[pos] = base36[quotient % base36.len];
                quotient /= base36.len;
            }
            name[0] = @intCast(@as(usize, 'a') + quotient);
            try many.append(std.testing.allocator, ' ');
            try many.appendSlice(std.testing.allocator, name[0..name_width]);
            try many.appendSlice(std.testing.allocator, "=''");
        }
        const first_name = [_]u8{ 'a', '0', '0', '0' };
        try many.append(std.testing.allocator, ' ');
        try many.appendSlice(std.testing.allocator, first_name[0..name_width]);
        try many.appendSlice(std.testing.allocator, "=''/>");
        try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));
    }

    // All 4097 distinct names below have the same length and first eight
    // bytes, so the pre-V19 large-name hash maps them to the same family.
    // Full-name Wyhash partitioning must preserve both uniqueness and exact
    // duplicate detection without relying on that prefix hash.
    const adversarial_unique_count: usize = 4097;
    const adversarial_name_len: usize = 11;
    const adversarial_unique_len = 2 + adversarial_unique_count * (adversarial_name_len + 4) + 2;
    const adversarial_duplicate_len = adversarial_unique_len - 2 + (adversarial_name_len + 6);
    if (adversarial_duplicate_len <= MaxInputLen) {
        many.clearRetainingCapacity();
        try many.appendSlice(std.testing.allocator, "<r");
        for (0..adversarial_unique_count) |index| {
            var suffix: [3]u8 = undefined;
            var quotient = index;
            var pos: usize = suffix.len;
            while (pos > 0) {
                pos -= 1;
                suffix[pos] = base36[quotient % base36.len];
                quotient /= base36.len;
            }
            try many.appendSlice(std.testing.allocator, " abcdefgh");
            try many.appendSlice(std.testing.allocator, &suffix);
            try many.appendSlice(std.testing.allocator, "=''");
        }
        try many.appendSlice(std.testing.allocator, "/>");
        try validated_doc.parse(many.items);

        many.items.len -= 2;
        try many.appendSlice(std.testing.allocator, " abcdefgh000=''/>");
        try std.testing.expectError(error.DuplicateAttribute, validated_doc.parse(many.items));
    }

    const permissive_opts: ParseOptions = .{ .non_destructive = true };
    var permissive_doc = initDoc(permissive_opts);
    defer permissive_doc.deinit();
    try permissive_doc.parse("<r a='1' a='2'/>");
}

test "validated validates XML declaration grammar" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
    var doc = initDoc(opts);
    defer doc.deinit();

    const invalid = [_][]const u8{
        "<?xml?><r/>",
        "<?xml encoding='UTF-8'?><r/>",
        "<?xml version='2.0'?><r/>",
        "<?xml version='1.'?><r/>",
        "<?xml version='1.0'encoding='UTF-8'?><r/>",
        "<?xml version='1.0' standalone='maybe'?><r/>",
        "<?xml version='1.0' extra='x'?><r/>",
        "<?xml version=1.0?><r/>",
    };
    for (invalid) |source| try std.testing.expectError(error.InvalidDeclaration, doc.parse(source));

    try doc.parse("<?xml version = '1.0' encoding='UTF-8' standalone=\"no\" ?><r/>");
    try doc.parse("<?xml version='1.23'?><r/>");
}

test "validated validates DOCTYPE grammar" {
    const opts: ParseOptions = .{
        .validate_well_formedness = true,
        .non_destructive = true,
    };
    var doc = initDoc(opts);
    defer doc.deinit();

    const invalid = [_][]const u8{
        "<!DOCTYPE><r/>",
        "<!DOCTYPEr><r/>",
        "<!DOCTYPE 1r><r/>",
        "<!DOCTYPE r garbage><r/>",
        "<!DOCTYPE r SYSTEM'urn:test'><r/>",
        "<!DOCTYPE r PUBLIC 'id'><r/>",
        "<!DOCTYPE r PUBLIC '^' 'sys'><r/>",
        "<!DOCTYPE r [junk]><r/>",
        "<!DOCTYPE r [<!FOO x>]><r/>",
        "<!DOCTYPE r [<![IGNORE[x]]>]><r/>",
        "<!DOCTYPE r [<!--a--b-->]><r/>",
        "<!DOCTYPE r [<!--a--->]><r/>",
        "<!DOCTYPE r [<?xml x?>]><r/>",
        "<!DOCTYPE r [<??>]><r/>",
        "<!DOCTYPE r [%missing]><r/>",
        "<!DOCTYPE r [<!ELEMENT r>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r ANYx>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r ()>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (a|)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (a,b|c)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (a b)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (#PCDATA|a)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (#PCDATA,a)*>]><r/>",
        "<!DOCTYPE r [<!ELEMENT \xC3\x97 EMPTY>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a UNKNOWN #IMPLIED>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a () #IMPLIED>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a NOTATION () #IMPLIED>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a (one|two)>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA 'x<y'>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA '&#0;'>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA '&#X41;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY x>]><r/>",
        "<!DOCTYPE r [<!ENTITY x PUBLIC 'id'>]><r/>",
        "<!DOCTYPE r [<!ENTITY %p 'x'>]><r/>",
        "<!DOCTYPE r [<!ENTITY % p SYSTEM 'x' NDATA n>]><r/>",
        "<!DOCTYPE r [<!ENTITY x '%p;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY x '&#xD800;'>]><r/>",
        "<!DOCTYPE r [<!ENTITY x '&#x110000;'>]><r/>",
        "<!DOCTYPE r [<!NOTATION n>]><r/>",
        "<!DOCTYPE r [<!NOTATION n SYSTEM>]><r/>",
        "<!DOCTYPE r [<!NOTATION n PUBLIC>]><r/>",
    };
    for (invalid) |source| try std.testing.expectError(error.InvalidDoctype, doc.parse(source));

    const valid = [_][]const u8{
        "<!DOCTYPE r SYSTEM 'urn:test'><r/>",
        "<!DOCTYPE r PUBLIC '-//Example//DTD Test 1.0//EN' 'urn:test' [<!ELEMENT r EMPTY>]><r/>",
        "<!DOCTYPE r []><r/>",
        "<!DOCTYPE r [<!--ok--><?pi data?><!ELEMENT r ANY>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (a,(b|c)+,d?)><!ELEMENT a EMPTY><!ELEMENT b EMPTY><!ELEMENT c EMPTY><!ELEMENT d EMPTY>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (#PCDATA)>]><r/>",
        "<!DOCTYPE r [<!ELEMENT r (#PCDATA|em|b)*>]><r/>",
        "<!DOCTYPE r [<!ATTLIST r a CDATA #IMPLIED b ID #REQUIRED c (one|two|3) 'one' n NOTATION (gif|jpg) #FIXED 'gif'>]><r/>",
        "<!DOCTYPE r [<!ENTITY x 'a&amp;&#x41;'><!ENTITY ext SYSTEM 'urn:x' NDATA n><!ENTITY % p 'x'><!NOTATION n PUBLIC 'id'>]><r/>",
        "<!DOCTYPE r [<!ENTITY % p SYSTEM 'urn:p'><!NOTATION n SYSTEM 'urn:n'><!NOTATION m PUBLIC 'id' 'urn:m'>]><r/>",
        "<!DOCTYPE r [<!ELEMENT \xC3\xA9l\xC3\xA9ment EMPTY>]><r/>",
    };
    for (valid) |source| try doc.parse(source);
}
