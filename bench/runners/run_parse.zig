const std = @import("std");
const zxml = @import("zxml");

pub const DomBenchMode = enum {
    validated,
    validated_trusted,
    permissive,
};

pub const StreamBenchMode = enum {
    validated,
    validated_trusted,
    permissive,
};

const dom_validated_options: zxml.ParseOptions = .{
    .validate_well_formedness = true,
};
const dom_validated_trusted_options: zxml.ParseOptions = .{
    .validate_well_formedness = true,
    .validate_xml_characters = false,
};
const dom_permissive_options: zxml.ParseOptions = .{};

fn elapsedNs(start: std.Io.Clock.Timestamp, finish: std.Io.Clock.Timestamp) u64 {
    const elapsed = start.durationTo(finish);
    return @intCast(@max(elapsed.raw.nanoseconds, 0));
}

fn runDomValidated(io: std.Io, alloc: std.mem.Allocator, input: []u8, iterations: usize) !u64 {
    var checksum: u64 = 0;
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..iterations) |_| {
        var doc = try dom_validated_options.parse(alloc, input);
        checksum +%= @as(u64, @intCast(doc.nodes.len));
        doc.deinit();
    }
    const finish = std.Io.Clock.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(checksum);
    return elapsedNs(start, finish);
}

fn runDomValidatedTrusted(io: std.Io, alloc: std.mem.Allocator, input: []u8, iterations: usize) !u64 {
    var checksum: u64 = 0;
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..iterations) |_| {
        var doc = try dom_validated_trusted_options.parse(alloc, input);
        checksum +%= @as(u64, @intCast(doc.nodes.len));
        doc.deinit();
    }
    const finish = std.Io.Clock.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(checksum);
    return elapsedNs(start, finish);
}

fn runDomPermissive(io: std.Io, alloc: std.mem.Allocator, input: []u8, iterations: usize) !u64 {
    var checksum: u64 = 0;
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..iterations) |_| {
        var doc = try dom_permissive_options.parse(alloc, input);
        checksum +%= @as(u64, @intCast(doc.nodes.len));
        doc.deinit();
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
        .validated => @call(.never_inline, runDomValidated, .{ io, alloc, input, iterations }),
        .validated_trusted => @call(.never_inline, runDomValidatedTrusted, .{ io, alloc, input, iterations }),
        .permissive => @call(.never_inline, runDomPermissive, .{ io, alloc, input, iterations }),
    };
}

pub fn runStreamParseFile(io: std.Io, path: []const u8, iterations: usize, mode: StreamBenchMode) !u64 {
    if (iterations == 0) return error.InvalidIterations;

    const alloc = std.heap.smp_allocator;
    const input = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
    defer alloc.free(input);

    return switch (mode) {
        .validated => @call(.never_inline, runStreamValidated, .{ io, alloc, input, iterations }),
        .validated_trusted => @call(.never_inline, runStreamValidatedTrusted, .{ io, alloc, input, iterations }),
        .permissive => @call(.never_inline, runStreamPermissive, .{ io, alloc, input, iterations }),
    };
}

fn runStreamValidated(io: std.Io, alloc: std.mem.Allocator, input: []const u8, iterations: usize) !u64 {
    const StreamValidated = zxml.Types(.{
        .validate_well_formedness = true,
    });
    const StreamingEventType = StreamValidated.StreamingEvent;
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

    var parser = StreamValidated.StreamingParser.init(alloc);
    defer parser.deinit();
    var ctx: Context = .{};
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..iterations) |_| try parser.parse(input, &ctx, Context.onNode);
    const finish = std.Io.Clock.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(ctx.checksum);
    std.mem.doNotOptimizeAway(ctx.count);
    return elapsedNs(start, finish);
}

fn runStreamValidatedTrusted(io: std.Io, alloc: std.mem.Allocator, input: []const u8, iterations: usize) !u64 {
    const StreamValidated = zxml.Types(.{
        .validate_well_formedness = true,
        .validate_xml_characters = false,
    });
    const StreamingEventType = StreamValidated.StreamingEvent;
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

    var parser = StreamValidated.StreamingParser.init(alloc);
    defer parser.deinit();
    var ctx: Context = .{};
    const start = std.Io.Clock.Timestamp.now(io, .awake);
    for (0..iterations) |_| try parser.parse(input, &ctx, Context.onNode);
    const finish = std.Io.Clock.Timestamp.now(io, .awake);
    std.mem.doNotOptimizeAway(ctx.checksum);
    std.mem.doNotOptimizeAway(ctx.count);
    return elapsedNs(start, finish);
}

fn runStreamPermissive(io: std.Io, alloc: std.mem.Allocator, input: []const u8, iterations: usize) !u64 {
    const StreamPermissive = zxml.Types(.{});
    const StreamingEventType = StreamPermissive.StreamingEvent;
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

    var parser = StreamPermissive.StreamingParser.init(alloc);
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
    try std.testing.expectError(error.InvalidIterations, runDomParseFile(std.testing.io, "does-not-exist.xml", 0, .permissive));
    try std.testing.expectError(error.InvalidIterations, runStreamParseFile(std.testing.io, "does-not-exist.xml", 0, .permissive));
}

test "all benchmark modes parse the smoke fixture" {
    inline for (std.meta.tags(DomBenchMode)) |mode| {
        _ = try runDomParseFile(std.testing.io, "bench/smoke.xml", 2, mode);
    }
    inline for (std.meta.tags(StreamBenchMode)) |mode| {
        _ = try runStreamParseFile(std.testing.io, "bench/smoke.xml", 2, mode);
    }
}
