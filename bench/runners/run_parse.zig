const std = @import("std");
const fastxml = @import("fastxml");

pub const BenchMode = enum {
    strict,
    turbo,
    stream_strict,
    stream_turbo,
};

pub fn runParseFile(io: std.Io, alloc: std.mem.Allocator, path: []const u8, iterations: usize, mode: BenchMode) !u64 {
    const options: fastxml.ParseOptions = .{};
    // Bench against the same concrete DOM type across all runs so the parser is
    // specialized once and the loop measures parse work instead of type setup.
    const Document = fastxml.Types(options).Document;
    const StreamStrict = fastxml.Types(.{
        .mode = .strict,
        .validate_closing_tags = true,
        .include_misc_nodes = true,
    });
    const StreamTurbo = fastxml.Types(.{
        .mode = .turbo,
        .include_misc_nodes = true,
    });
    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(input);
    var doc = Document.init(alloc);
    defer doc.deinit();
    var strict_stream = StreamStrict.StreamParser.init(alloc);
    defer strict_stream.deinit();
    var turbo_stream = StreamTurbo.StreamParser.init(alloc);
    defer turbo_stream.deinit();

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
        .stream_strict => {
            const StreamNode = StreamStrict.StreamNode;
            const Callback = struct {
                fn onNode(_: *const StreamNode) bool {
                    return true;
                }
            };
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                try strict_stream.parse(input, {}, Callback.onNode);
            }
        },
        .stream_turbo => {
            const StreamNode = StreamTurbo.StreamNode;
            const Callback = struct {
                fn onNode(_: *const StreamNode) bool {
                    return true;
                }
            };
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                try turbo_stream.parse(input, {}, Callback.onNode);
            }
        },
    }
    const end = std.Io.Clock.Timestamp.now(io, .awake);
    const elapsed = start.durationTo(end);
    return @intCast(@max(elapsed.raw.nanoseconds, 0));
}
