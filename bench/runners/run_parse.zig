const std = @import("std");
const zxml = @import("zxml");

pub const DomBenchMode = enum {
    strict,
    turbo,
};

pub const StreamBenchMode = enum {
    strict,
    turbo,
};

const options: zxml.ParseOptions = .{};
const Document = zxml.Types(options).Document;

fn elapsedNs(start: std.Io.Clock.Timestamp, finish: std.Io.Clock.Timestamp) u64 {
    const elapsed = start.durationTo(finish);
    return @intCast(@max(elapsed.raw.nanoseconds, 0));
}

fn runDomStrict(io: std.Io, alloc: std.mem.Allocator, input: []const u8, iterations: usize) !u64 {
    var doc = Document.init(alloc);
    defer doc.deinit();

    var checksum: u64 = 0;
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..iterations) |_| {
        try doc.parse(input, .{
            .mode = .strict,
            .validate_closing_tags = true,
            .include_misc_nodes = true,
        });
        checksum +%= @as(u64, @intCast(doc.nodes.items.len));
        checksum +%= @as(u64, @intCast(doc.attrs.items.len));
    }
    const finish = std.Io.Clock.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(checksum);
    return elapsedNs(start, finish);
}

fn runDomTurbo(io: std.Io, alloc: std.mem.Allocator, input: []const u8, iterations: usize) !u64 {
    var doc = Document.init(alloc);
    defer doc.deinit();

    var checksum: u64 = 0;
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..iterations) |_| {
        try doc.parse(input, .{
            .mode = .turbo,
            .include_misc_nodes = true,
        });
        checksum +%= @as(u64, @intCast(doc.nodes.items.len));
        checksum +%= @as(u64, @intCast(doc.attrs.items.len));
    }
    const finish = std.Io.Clock.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(checksum);
    return elapsedNs(start, finish);
}

pub fn runDomParseFile(io: std.Io, path: []const u8, iterations: usize, mode: DomBenchMode) !u64 {
    if (iterations == 0) return error.InvalidIterations;

    const alloc = std.heap.smp_allocator;
    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(input);

    return switch (mode) {
        .strict => @call(.never_inline, runDomStrict, .{ io, alloc, input, iterations }),
        .turbo => @call(.never_inline, runDomTurbo, .{ io, alloc, input, iterations }),
    };
}

pub fn runStreamParseFile(io: std.Io, path: []const u8, iterations: usize, mode: StreamBenchMode) !u64 {
    if (iterations == 0) return error.InvalidIterations;

    const alloc = std.heap.smp_allocator;
    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(input);

    return switch (mode) {
        .strict => @call(.never_inline, runStreamStrict, .{ io, alloc, input, iterations }),
        .turbo => @call(.never_inline, runStreamTurbo, .{ io, alloc, input, iterations }),
    };
}

fn runStreamStrict(io: std.Io, alloc: std.mem.Allocator, input: []const u8, iterations: usize) !u64 {
    const StreamStrict = zxml.Types(.{
        .mode = .strict,
        .validate_closing_tags = true,
        .include_misc_nodes = true,
    });
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

    var parser = StreamStrict.StreamingParser.init(alloc);
    defer parser.deinit();
    var ctx: Context = .{};
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..iterations) |_| try parser.parse(input, &ctx, Context.onNode);
    const finish = std.Io.Clock.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(ctx.checksum);
    std.mem.doNotOptimizeAway(ctx.count);
    return elapsedNs(start, finish);
}

fn runStreamTurbo(io: std.Io, alloc: std.mem.Allocator, input: []const u8, iterations: usize) !u64 {
    const StreamTurbo = zxml.Types(.{
        .mode = .turbo,
        .include_misc_nodes = true,
    });
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

    var parser = StreamTurbo.StreamingParser.init(alloc);
    defer parser.deinit();
    var ctx: Context = .{};
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..iterations) |_| try parser.parse(input, &ctx, Context.onNode);
    const finish = std.Io.Clock.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(ctx.checksum);
    std.mem.doNotOptimizeAway(ctx.count);
    return elapsedNs(start, finish);
}

test "benchmark runners reject zero iterations before file access" {
    try std.testing.expectError(error.InvalidIterations, runDomParseFile(std.testing.io, "does-not-exist.xml", 0, .turbo));
    try std.testing.expectError(error.InvalidIterations, runStreamParseFile(std.testing.io, "does-not-exist.xml", 0, .turbo));
}

test "all benchmark modes parse the smoke fixture" {
    inline for (std.meta.tags(DomBenchMode)) |mode| {
        _ = try runDomParseFile(std.testing.io, "bench/smoke.xml", 2, mode);
    }
    inline for (std.meta.tags(StreamBenchMode)) |mode| {
        _ = try runStreamParseFile(std.testing.io, "bench/smoke.xml", 2, mode);
    }
}
