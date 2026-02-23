const std = @import("std");
const fastxml = @import("fastxml");

fn run(path: []const u8, iterations: usize, mode: []const u8) !u64 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const input = try std.fs.cwd().readFileAlloc(alloc, path, std.math.maxInt(usize));
    defer alloc.free(input);

    const working = try alloc.alloc(u8, input.len);
    defer alloc.free(working);

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    const start = std.time.nanoTimestamp();
    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        @memcpy(working, input);
        var doc = fastxml.Document.init(arena.allocator());
        defer doc.deinit();

        if (std.mem.eql(u8, mode, "strict")) {
            try doc.parse(working, .{ .mode = .strict, .validate_closing_tags = true, .store_parent_pointers = true });
        } else {
            try doc.parse(working, .{
                .mode = .turbo,
                .store_parent_pointers = false,
                .include_misc_nodes = false,
            });
        }

        _ = arena.reset(.retain_capacity);
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

    if (args.len != 4) {
        std.debug.print("usage: {s} <strict|turbo> <xml-file> <iterations>\n", .{args[0]});
        std.process.exit(2);
    }

    const total_ns = try run(args[2], try std.fmt.parseInt(usize, args[3], 10), args[1]);
    std.debug.print("{d}\n", .{total_ns});
}
