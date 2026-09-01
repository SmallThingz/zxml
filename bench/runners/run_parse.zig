const std = @import("std");
const zxml = @import("zxml");

pub const BenchMode = enum {
    strict,
    turbo,
    stream_strict,
    stream_turbo,
};

pub fn runParseFile(io: std.Io, alloc: std.mem.Allocator, path: []const u8, iterations: usize, mode: BenchMode) !u64 {
    if (iterations == 0) return error.InvalidIterations;
    const options: zxml.ParseOptions = .{};
    // Bench against the same concrete DOM type across all runs so the parser is
    // specialized once and the loop measures parse work instead of type setup.
    const Document = zxml.Types(options).Document;
    const StreamStrict = zxml.Types(.{
        .mode = .strict,
        .validate_closing_tags = true,
        .include_misc_nodes = true,
    });
    const StreamTurbo = zxml.Types(.{
        .mode = .turbo,
        .include_misc_nodes = true,
    });
    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(input);

    var final_checksum: u64 = 0;
    var final_count: u64 = 0;
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    switch (mode) {
        .strict => {
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                var doc = Document.init(alloc);
                defer doc.deinit();
                try doc.parse(input, .{
                    .mode = .strict,
                    .validate_closing_tags = true,
                    // Benchmark the full payload. Skipping CDATA/comment/PI
                    // nodes makes some real-world feeds artificially cheap.
                    .include_misc_nodes = true,
                });
                // Keep the produced DOM observably live. This is deliberately
                // O(1): walking the tree would benchmark traversal as well as
                // parsing, while leaving the result entirely unused gives an
                // optimizer room to discard dead construction work.
                final_count +%= 1;
                final_checksum +%= @as(u64, @intCast(doc.nodes.items.len));
                final_checksum +%= @as(u64, @intCast(doc.attrs.items.len));
            }
        },
        .turbo => {
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                var doc = Document.init(alloc);
                defer doc.deinit();
                try doc.parse(input, .{
                    .mode = .turbo,
                    .include_misc_nodes = true,
                });
                final_count +%= 1;
                final_checksum +%= @as(u64, @intCast(doc.nodes.items.len));
                final_checksum +%= @as(u64, @intCast(doc.attrs.items.len));
            }
        },
        .stream_strict => {
            const StreamingEventType = StreamStrict.StreamingEvent;
            const Context = struct {
                checksum: u64 = 0,
                count: u64 = 0,

                fn onNode(self: *@This(), node: *const StreamingEventType) bool {
                    self.count +%= 1;
                    self.checksum +%= @as(u64, @intFromEnum(node.kind)) +% 1;
                    switch (node.kind) {
                        .element => {
                            self.checksum +%= @as(u64, node.name.end - node.name.start);
                            self.checksum +%= @as(u64, node.data.end - node.data.start);
                        },
                        else => self.checksum +%= @as(u64, node.data.end - node.data.start),
                    }
                    return true;
                }
            };
            var ctx: Context = .{};
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                var strict_stream = StreamStrict.StreamingParser.init(alloc);
                defer strict_stream.deinit();
                try strict_stream.parse(input, &ctx, Context.onNode);
            }
            final_checksum = ctx.checksum;
            final_count = ctx.count;
        },
        .stream_turbo => {
            const StreamingEventType = StreamTurbo.StreamingEvent;
            const Context = struct {
                checksum: u64 = 0,
                count: u64 = 0,

                fn onNode(self: *@This(), node: *const StreamingEventType) bool {
                    self.count +%= 1;
                    self.checksum +%= @as(u64, @intFromEnum(node.kind)) +% 1;
                    switch (node.kind) {
                        .element => {
                            self.checksum +%= @as(u64, node.name.end - node.name.start);
                            self.checksum +%= @as(u64, node.data.end - node.data.start);
                        },
                        else => self.checksum +%= @as(u64, node.data.end - node.data.start),
                    }
                    return true;
                }
            };
            var ctx: Context = .{};
            var i: usize = 0;
            while (i < iterations) : (i += 1) {
                var turbo_stream = StreamTurbo.StreamingParser.init(alloc);
                defer turbo_stream.deinit();
                try turbo_stream.parse(input, &ctx, Context.onNode);
            }
            final_checksum = ctx.checksum;
            final_count = ctx.count;
        },
    }
    const end = std.Io.Clock.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(final_checksum);
    std.mem.doNotOptimizeAway(final_count);
    const elapsed = start.durationTo(end);
    return @intCast(@max(elapsed.raw.nanoseconds, 0));
}

test "runParseFile rejects zero iterations before file access" {
    try std.testing.expectError(
        error.InvalidIterations,
        runParseFile(std.testing.io, std.testing.allocator, "does-not-exist.xml", 0, .turbo),
    );
}

test "all benchmark modes parse the smoke fixture" {
    inline for (std.meta.tags(BenchMode)) |mode| {
        _ = try runParseFile(std.testing.io, std.testing.allocator, "bench/smoke.xml", 2, mode);
    }
}
