const std = @import("std");
const zxml = @import("zxml");

pub fn run() !void {
    var src = "<root id='r'><child>text</child></root>".*;
    const options: zxml.ParseOptions = .{ .validate_well_formedness = true };
    var doc = try options.parse(std.testing.allocator, &src);
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
