const std = @import("std");
const conformance = @import("conformance.zig");

// Legacy wrapper kept for compatibility with older command wiring.
pub fn runCompliance(alloc: std.mem.Allocator, args: []const []const u8) !void {
    try conformance.runConformance(alloc, args);
}
