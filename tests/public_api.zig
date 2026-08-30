const std = @import("std");
const zxml = @import("zxml");

fn contains(comptime names: []const []const u8, comptime needle: []const u8) bool {
    inline for (names) |name| if (std.mem.eql(u8, name, needle)) return true;
    return false;
}

fn assertFnCoverage(comptime T: type, comptime expected: []const []const u8) void {
    comptime {
        var actual: usize = 0;
        for (std.meta.declarations(T)) |decl| {
            const value = @field(T, decl.name);
            if (@typeInfo(@TypeOf(value)) != .@"fn") continue;
            actual += 1;
            if (!contains(expected, decl.name)) {
                @compileError("public API function is not exercised: " ++ @typeName(T) ++ "." ++ decl.name);
            }
        }
        if (actual != expected.len) @compileError("public API coverage list contains a missing/non-function declaration for " ++ @typeName(T));
    }
}

const Sink = struct {
    bytes: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,

    fn deinit(self: *@This()) void {
        self.bytes.deinit(self.allocator);
    }
    pub fn writeAll(self: *@This(), data: []const u8) !void {
        try self.bytes.appendSlice(self.allocator, data);
    }
};

fn exerciseTypes(comptime opts: zxml.ParseOptions) !void {
    const T = zxml.Types(opts);

    assertFnCoverage(T.Span, &.{ "len", "isEmpty", "slice" });
    assertFnCoverage(T.RawNode, &.{ "valueSpan", "attributeSpan" });
    assertFnCoverage(T.Attribute, &.{ "nameSlice", "valueRawSlice", "namespacePrefix", "localName", "value", "write" });
    assertFnCoverage(T.Node, &.{
        "nameSlice",         "namespacePrefix", "localName",    "namespaceUri", "valueRawSlice", "value",
        "firstChild",        "lastChild",       "nextSibling",  "prevSibling",  "parentNode",    "getAttributeValueRaw",
        "getAttributeValue", "firstAttribute",  "innerTextRaw", "innerText",    "querySelector", "querySelectorAll",
        "write",
    });
    assertFnCoverage(T.Document, &.{
        "init", "deinit", "clear", "parse", "parseDiagnostic", "registerDoctypeEntities", "root", "nodeAt", "write", "reserveForInput",
    });
    assertFnCoverage(T.StreamingAttribute, &.{ "nameSlice", "valueRawSlice" });
    assertFnCoverage(T.StreamingAttributeIterator, &.{"next"});
    assertFnCoverage(T.StreamingEvent, &.{ "nameSlice", "valueRawSlice", "attributes", "getAttributeValueRaw", "leadingTextRaw", "followingTextRaw" });
    assertFnCoverage(T.StreamingParser, &.{ "init", "deinit", "parse", "clear", "save", "restore", "parseAvailable", "finish" });

    const source = "<!DOCTYPE ns:r [<!ENTITY e 'decoded'>]><ns:r xmlns:ns='urn:test' a='&amp;'><x>text</x><y/></ns:r>";
    var doc = T.Document.init(std.testing.allocator);
    defer doc.deinit();
    try doc.reserveForInput(source.len);
    try doc.parse(source, opts);

    _ = (T.RawNode{ .kind = .text }).valueSpan();
    _ = (T.RawNode{ .kind = .element }).attributeSpan();
    const span: T.Span = .{ .start = 0, .end = 2 };
    _ = span.len();
    _ = span.isEmpty();
    _ = span.slice("abcd");

    const root_doc = doc.root().?;
    _ = root_doc.nameSlice();
    const root = root_doc.querySelector("ns:r").?;
    _ = root.nameSlice();
    _ = root.namespacePrefix();
    _ = root.localName();
    _ = root.namespaceUri();
    _ = root.valueRawSlice();
    const root_value = try root.value(std.testing.allocator);
    std.testing.allocator.free(root_value);
    _ = root.firstChild();
    _ = root.lastChild();
    _ = root.nextSibling();
    _ = root.prevSibling();
    _ = root.parentNode();
    _ = root.getAttributeValueRaw("a");
    if (try root.getAttributeValue(std.testing.allocator, "a")) |value| std.testing.allocator.free(value);
    const attr = root.firstAttribute().?;
    _ = attr.nameSlice();
    _ = attr.valueRawSlice();
    _ = attr.namespacePrefix();
    _ = attr.localName();
    const attr_value = try attr.value(std.testing.allocator);
    std.testing.allocator.free(attr_value);
    _ = root.innerTextRaw();
    const inner = try root.innerText(std.testing.allocator);
    std.testing.allocator.free(inner);
    _ = root.querySelector("x");
    const matches = try root.querySelectorAll(std.testing.allocator, "x");
    std.testing.allocator.free(matches);
    _ = doc.nodeAt(0);

    var sink: Sink = .{ .allocator = std.testing.allocator };
    defer sink.deinit();
    try attr.write(&sink);
    try root.write(&sink);
    try doc.write(&sink);

    try doc.registerDoctypeEntities(" ns:r [<!ENTITY e 'decoded'>]");
    const diag = doc.parseDiagnostic("<r>", .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true }).?;
    _ = diag.location();
    _ = diag.context(4);
    doc.clear();

    const Ctx = struct {
        fn onNode(_: *@This(), event: T.StreamingEvent) bool {
            _ = event.nameSlice();
            _ = event.valueRawSlice();
            var attrs = event.attributes();
            if (attrs.next()) |a| {
                _ = a.nameSlice();
                _ = a.valueRawSlice();
            }
            _ = event.getAttributeValueRaw("a");
            _ = event.leadingTextRaw();
            _ = event.followingTextRaw() catch {};
            return true;
        }
    };
    var ctx: Ctx = .{};
    var stream = T.StreamingParser.init(std.testing.allocator);
    defer stream.deinit();
    try stream.parse("<r a='1'>text<x/></r>", &ctx, Ctx.onNode);
    stream.clear();
    _ = try stream.parseAvailable("<r>", &ctx, Ctx.onNode);
    const saved = stream.save();
    _ = try stream.parseAvailable("<r><x/>", &ctx, Ctx.onNode);
    stream.restore(saved);
    _ = try stream.parseAvailable("<r></r>", &ctx, Ctx.onNode);
    try stream.finish();
}

test "external package surface compiles and executes every public function" {
    std.testing.refAllDecls(zxml);
    _ = zxml.MaxInputLen;
    _ = zxml.InvalidIndex;
    const mode: zxml.ParseMode = .strict;
    _ = mode;
    const node_kind: zxml.NodeType = .element;
    _ = node_kind;
    const parse_err: zxml.ParseError = error.ExpectedGt;
    try std.testing.expect(parse_err == error.ExpectedGt);

    assertFnCoverage(zxml, &.{"Types"});
    assertFnCoverage(zxml.ParseOptions, &.{ "parse", "Document" });
    assertFnCoverage(zxml.ParseDiagnostic, &.{ "location", "context" });

    const opts: zxml.ParseOptions = .{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true, .expand_dtd_entities = true };
    _ = opts.Document();
    var owned = try opts.parse(std.testing.allocator, "<r/>");
    owned.deinit();
    try exerciseTypes(opts);
}

test "public parser functions instantiate in turbo and strict configurations" {
    try exerciseTypes(.{ .mode = .turbo });
    try exerciseTypes(.{ .mode = .strict, .validate_closing_tags = true, .require_closed_elements_on_eof = true });
}
