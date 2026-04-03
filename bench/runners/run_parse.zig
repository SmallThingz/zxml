const std = @import("std");
const fastxml = @import("fastxml");

pub const BenchMode = enum {
    strict,
    turbo,
};

pub fn runParseFile(io: std.Io, alloc: std.mem.Allocator, path: []const u8, iterations: usize, mode: BenchMode) !u64 {
    const options: fastxml.ParseOptions = .{};
    const Document = fastxml.Types(options).Document;
    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(input);
    var doc = Document.init(alloc);
    defer doc.deinit();

    const start = std.Io.Clock.Timestamp.now(io, .awake);
    switch (mode) {
        .strict => {
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                try doc.parse(input, .{
                    .mode = .strict,
                    .validate_closing_tags = true,
                    // Benchmark the full payload. Skipping CDATA/comment/PI
                    // nodes makes some real-world feeds artificially cheap.
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
    const end = std.Io.Clock.Timestamp.now(io, .awake);
    const elapsed = start.durationTo(end);
    return @intCast(@max(elapsed.raw.nanoseconds, 0));
}
