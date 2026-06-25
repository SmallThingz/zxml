const std = @import("std");
const zxml = @import("zxml");

pub fn run() !void {
    const src = "<root id='r'><child>text</child></root>";
    const options: zxml.ParseOptions = .{ .mode = .strict, .validate_closing_tags = true };
    var doc = try options.parse(std.testing.allocator, src);
    defer doc.deinit();

    const root = doc.nodeAt(1).?;
    try std.testing.expectEqualStrings("root", root.nameSlice());
    try std.testing.expectEqualStrings("r", root.getAttributeValueRaw("id").?);

    const child = root.firstChild().?;
    try std.testing.expectEqualStrings("child", child.nameSlice());
    try std.testing.expectEqualStrings("text", child.firstChild().?.valueRawSlice());
}

test "basic parse" {
    try run();
}
