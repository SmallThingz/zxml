const std = @import("std");
const fastxml = @import("fastxml");
const Io = std.Io;

const BenchMode = enum {
    strict,
    turbo,
};

pub fn runParseFile(io: Io, alloc: std.mem.Allocator, path: []const u8, iterations: usize, mode: BenchMode) !u64 {
    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(input);
    var doc = fastxml.Document.init(alloc);
    defer doc.deinit();

    const start = Io.Clock.Timestamp.now(io, .awake);
    switch (mode) {
        .strict => {
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                try doc.parse(input, .{
                    .mode = .strict,
                    .validate_closing_tags = true,
                    .store_parent_pointers = false,
                    .include_misc_nodes = false,
                });
            }
        },
        .turbo => {
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                try doc.parse(input, .{
                    .mode = .turbo,
                    .store_parent_pointers = false,
                    .include_misc_nodes = false,
                });
            }
        },
    }
    const end = Io.Clock.Timestamp.now(io, .awake);
    const elapsed = start.durationTo(end);

    return @intCast(@max(elapsed.raw.nanoseconds, 0));
}

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
        const mode: BenchMode = if (std.mem.eql(u8, args.items[2], "strict"))
            .strict
        else if (std.mem.eql(u8, args.items[2], "turbo"))
            .turbo
        else
            return error.InvalidBenchMode;
        const iterations = try std.fmt.parseInt(usize, args.items[4], 10);
        const total_ns = try runParseFile(init.io, alloc, args.items[3], iterations, mode);
        std.debug.print("{d}\n", .{total_ns});
        return;
    }

    if (args.items.len == 3) {
        const iterations = try std.fmt.parseInt(usize, args.items[2], 10);
        const total_ns = try runParseFile(init.io, alloc, args.items[1], iterations, .turbo);
        std.debug.print("{d}\n", .{total_ns});
        return;
    }

    std.debug.print("usage:\n  {s} <xml-file> <iterations>\n  {s} parse <strict|turbo> <xml-file> <iterations>\n", .{ args.items[0], args.items[0] });
    return error.InvalidArguments;
}
