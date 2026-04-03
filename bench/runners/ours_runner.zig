const std = @import("std");
const fastxml = @import("fastxml");
const Io = std.Io;

const Mode = enum {
    strict,
    turbo,
};

fn run(io: Io, alloc: std.mem.Allocator, path: []const u8, iterations: usize, mode: Mode) !u64 {
    const options: fastxml.ParseOptions = .{};
    const Document = fastxml.GetDocument(options);
    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(input);
    var doc = Document.init(alloc);
    defer doc.deinit();

    const start = Io.Clock.Timestamp.now(io, .awake);
    switch (mode) {
        .strict => {
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                try doc.parse(input, .{
                    .mode = .strict,
                    .validate_closing_tags = true,
                    // Benchmark the full payload. Skipping CDATA/comment/PI nodes
                    // makes some real-world feeds artificially cheap.
                    .include_misc_nodes = true,
                });
            }
        },
        .turbo => {
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                try doc.parse(input, .{
                    .mode = .turbo,
                    .include_misc_nodes = true,
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

    if (args.items.len != 4) {
        std.debug.print("usage: {s} <strict|turbo> <xml-file> <iterations>\n", .{args.items[0]});
        return error.InvalidArguments;
    }

    const mode: Mode = if (std.mem.eql(u8, args.items[1], "strict"))
        .strict
    else if (std.mem.eql(u8, args.items[1], "turbo"))
        .turbo
    else
        return error.InvalidArguments;

    const total_ns = try run(init.io, alloc, args.items[2], try std.fmt.parseInt(usize, args.items[3], 10), mode);
    std.debug.print("{d}\n", .{total_ns});
}
