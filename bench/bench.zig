const std = @import("std");
const run_parse = @import("runners/run_parse.zig");

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(alloc);

    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    while (it.next()) |arg| {
        try args.append(alloc, try alloc.dupe(u8, arg));
    }

    if (args.items.len == 5 and std.mem.eql(u8, args.items[1], "parse")) {
        const mode: run_parse.BenchMode = if (std.mem.eql(u8, args.items[2], "strict"))
            run_parse.BenchMode.strict
        else if (std.mem.eql(u8, args.items[2], "turbo"))
            run_parse.BenchMode.turbo
        else if (std.mem.eql(u8, args.items[2], "stream-strict"))
            run_parse.BenchMode.stream_strict
        else if (std.mem.eql(u8, args.items[2], "stream-turbo"))
            run_parse.BenchMode.stream_turbo
        else
            return error.InvalidBenchMode;
        const iterations = try std.fmt.parseInt(usize, args.items[4], 10);
        const total_ns = try run_parse.runParseFile(init.io, alloc, args.items[3], iterations, mode);
        try printMeasurement(init.io, total_ns);
        return;
    }

    if (args.items.len == 3) {
        const iterations = try std.fmt.parseInt(usize, args.items[2], 10);
        const total_ns = try run_parse.runParseFile(init.io, alloc, args.items[1], iterations, .turbo);
        try printMeasurement(init.io, total_ns);
        return;
    }

    std.debug.print(
        "usage:\n  {s} <xml-file> <iterations>\n  {s} parse <strict|turbo|stream-strict|stream-turbo> <xml-file> <iterations>\n",
        .{ args.items[0], args.items[0] },
    );
    return error.InvalidArguments;
}

fn printMeasurement(io: std.Io, total_ns: u64) !void {
    var stdout_buffer: [64]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    try stdout_writer.interface.print("{d}\n", .{total_ns});
    try stdout_writer.interface.flush();
}
