const std = @import("std");
const fastxml = @import("fastxml");

fn run(path: []const u8, iterations: usize, mode: []const u8) !u64 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const input = try std.fs.cwd().readFileAlloc(alloc, path, std.math.maxInt(usize));
    defer alloc.free(input);
    var doc = fastxml.Document.init(alloc);
    defer doc.deinit();

    const start = std.time.nanoTimestamp();
    if (std.mem.eql(u8, mode, "strict")) {
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            try doc.parse(input, .{
                .mode = .strict,
                .validate_closing_tags = true,
                .store_parent_pointers = false,
                .include_misc_nodes = false,
            });
        }
    } else {
        var i: usize = 0;
        while (i < iterations) : (i += 1) {
            try doc.parse(input, .{
                .mode = .turbo,
                .store_parent_pointers = false,
                .include_misc_nodes = false,
            });
        }
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
