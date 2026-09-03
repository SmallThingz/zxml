const std = @import("std");
const run_parse = @import("runners/run_parse.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(alloc);

    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    while (it.next()) |arg| try args.append(alloc, try alloc.dupe(u8, arg));

    if (args.items.len != 5 or !std.mem.eql(u8, args.items[1], "parse")) return error.InvalidArguments;
    const mode: run_parse.StreamBenchMode = if (std.mem.eql(u8, args.items[2], "strict"))
        .strict
    else if (std.mem.eql(u8, args.items[2], "strict-trusted"))
        .strict_trusted
    else if (std.mem.eql(u8, args.items[2], "turbo"))
        .turbo
    else
        return error.InvalidBenchMode;
    const iterations = try std.fmt.parseInt(usize, args.items[4], 10);
    const total_ns = try run_parse.runStreamParseFile(init.io, args.items[3], iterations, mode);

    var stdout_buffer: [64]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout_writer.interface.print("{d}\n", .{total_ns});
    try stdout_writer.interface.flush();
}
