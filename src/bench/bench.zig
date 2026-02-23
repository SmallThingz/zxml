const std = @import("std");
const fastxml = @import("fastxml");

const BenchMode = enum {
    strict,
    turbo,
};

fn parseMode(arg: []const u8) !BenchMode {
    if (std.mem.eql(u8, arg, "strict")) return .strict;
    if (std.mem.eql(u8, arg, "turbo")) return .turbo;
    return error.InvalidBenchMode;
}

pub fn runParseFile(path: []const u8, iterations: usize, mode: BenchMode) !u64 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const input = try std.fs.cwd().readFileAlloc(alloc, path, std.math.maxInt(usize));
    defer alloc.free(input);
    var doc = fastxml.Document.init(alloc);
    defer doc.deinit();

    const start = std.time.nanoTimestamp();
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
    const end = std.time.nanoTimestamp();

    return @intCast(end - start);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len == 5 and std.mem.eql(u8, args[1], "parse")) {
        const mode = try parseMode(args[2]);
        const iterations = try std.fmt.parseInt(usize, args[4], 10);
        const total_ns = try runParseFile(args[3], iterations, mode);
        std.debug.print("{d}\n", .{total_ns});
        return;
    }

    if (args.len == 3) {
        const iterations = try std.fmt.parseInt(usize, args[2], 10);
        const total_ns = try runParseFile(args[1], iterations, .turbo);
        std.debug.print("{d}\n", .{total_ns});
        return;
    }

    std.debug.print("usage:\n  {s} <xml-file> <iterations>\n  {s} parse <strict|turbo> <xml-file> <iterations>\n", .{ args[0], args[0] });
    std.process.exit(2);
}
