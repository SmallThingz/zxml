const std = @import("std");
const run_parse = @import("run_parse.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(alloc);

    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    while (it.next()) |arg| {
        try args.append(alloc, try alloc.dupe(u8, arg));
    }

    if (args.items.len != 4) {
        std.debug.print("usage: {s} <strict|turbo> <xml-file> <iterations>\n", .{args.items[0]});
        return error.InvalidArguments;
    }

    const mode: run_parse.BenchMode = if (std.mem.eql(u8, args.items[1], "strict"))
        .strict
    else if (std.mem.eql(u8, args.items[1], "turbo"))
        .turbo
    else
        return error.InvalidArguments;

    const total_ns = try run_parse.runParseFile(init.io, alloc, args.items[2], try std.fmt.parseInt(usize, args.items[3], 10), mode);
    std.debug.print("{d}\n", .{total_ns});
}
