const std = @import("std");
const builtin = @import("builtin");

pub const std_options: std.Options = .{
    .enable_segfault_handler = false,
    .signal_stack_size = null,
};

pub const panic = std.debug.FullPanic(panicHandler);

const default_job_cap: usize = 16;

fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    var out_buf: [512]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(std.Options.debug_io, &out_buf);
    stderr.interface.writeAll(msg) catch return;
    stderr.interface.flush() catch return;
}

pub fn fuzz(
    context: anytype,
    comptime testOne: fn (context: @TypeOf(context), smith: *std.testing.Smith) anyerror!void,
    fuzz_opts: std.testing.FuzzInputOptions,
) anyerror!void {
    if (comptime builtin.fuzz) {
        return fuzzBuiltin(context, testOne, fuzz_opts);
    }

    if (fuzz_opts.corpus.len == 0) {
        var smith: std.testing.Smith = .{ .in = "" };
        return testOne(context, &smith);
    }

    for (fuzz_opts.corpus) |input| {
        var smith: std.testing.Smith = .{ .in = input };
        try testOne(context, &smith);
    }
}

fn fuzzBuiltin(
    context: anytype,
    comptime testOne: fn (context: @TypeOf(context), smith: *std.testing.Smith) anyerror!void,
    fuzz_opts: std.testing.FuzzInputOptions,
) anyerror!void {
    const fuzz_abi = std.Build.abi.fuzz;
    const Smith = std.testing.Smith;
    const Ctx = @TypeOf(context);

    const Wrapper = struct {
        var ctx: Ctx = undefined;
        pub fn testOneC() callconv(.c) void {
            var smith: Smith = .{ .in = null };
            testOne(ctx, &smith) catch {};
        }
    };

    Wrapper.ctx = context;

    var cache_dir: []const u8 = ".";
    var map_opt: ?std.process.Environ.Map = null;
    if (std.testing.environ.createMap(std.testing.allocator)) |map| {
        map_opt = map;
        if (map.get("ZIG_CACHE_DIR")) |v| {
            cache_dir = v;
        } else if (map.get("ZIG_GLOBAL_CACHE_DIR")) |v| {
            cache_dir = v;
        }
    } else |_| {}

    fuzz_abi.fuzzer_init(.fromSlice(cache_dir));

    const test_name = @typeName(@TypeOf(testOne));
    fuzz_abi.fuzzer_set_test(Wrapper.testOneC, .fromSlice(test_name));

    for (fuzz_opts.corpus) |input| {
        fuzz_abi.fuzzer_new_input(.fromSlice(input));
    }

    fuzz_abi.fuzzer_main(.forever, 0);

    if (map_opt) |*m| m.deinit();
}

pub fn main(init: std.process.Init) void {
    const code = mainImpl(init) catch |err| blk: {
        print("test-runner fatal: {s}\n", .{@errorName(err)});
        break :blk @as(u8, 1);
    };
    std.process.exit(code);
}

fn mainImpl(init: std.process.Init) !u8 {
    const threaded = std.Io.Threaded.init(init.gpa, .{
        .argv0 = .init(init.minimal.args),
        .environ = init.minimal.environ,
    });
    std.testing.io_instance = threaded;
    std.testing.environ = init.minimal.environ;

    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);

    const argv0_z = arg_it.next() orelse "test-runner";
    const argv0 = argv0_z[0..argv0_z.len];

    var child_test_name: ?[]const u8 = null;
    var filter: ?[]const u8 = null;
    var exclude_filters: std.ArrayList([]const u8) = .empty;
    var jobs: ?usize = null;
    var seed: ?u32 = null;

    while (arg_it.next()) |arg_z| {
        const arg = arg_z[0..arg_z.len];
        if (std.mem.startsWith(u8, arg, "--fastxml-match=")) {
            const idx = std.mem.indexOfScalar(u8, arg, '=') orelse unreachable;
            filter = arg[idx + 1 ..];
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--fastxml-skip=")) {
            const idx = std.mem.indexOfScalar(u8, arg, '=') orelse unreachable;
            try exclude_filters.append(init.gpa, arg[idx + 1 ..]);
            continue;
        }
        if (std.mem.eql(u8, arg, "--fastxml-run-test")) {
            const name_z = arg_it.next() orelse return error.MissingTestName;
            child_test_name = name_z[0..name_z.len];
        } else if (std.mem.eql(u8, arg, "--fastxml-match")) {
            const f_z = arg_it.next() orelse return error.MissingFilter;
            filter = f_z[0..f_z.len];
        } else if (std.mem.eql(u8, arg, "--fastxml-skip")) {
            const f_z = arg_it.next() orelse return error.MissingFilter;
            try exclude_filters.append(init.gpa, f_z[0..f_z.len]);
        } else if (std.mem.eql(u8, arg, "--jobs")) {
            const j_z = arg_it.next() orelse return error.MissingJobs;
            jobs = try parseUsize(j_z[0..j_z.len]);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            const s_z = arg_it.next() orelse return error.MissingSeed;
            seed = try parseU32(s_z[0..s_z.len]);
        } else if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return 0;
        }
    }

    if (child_test_name) |name| {
        return runSingleTest(name, seed);
    }

    try runAllTests(init.gpa, init.io, argv0, filter, exclude_filters.items, jobs, seed);
    return 0;
}

fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    std.debug.defaultPanic(msg, first_trace_addr);
}

fn parseUsize(s: []const u8) !usize {
    return std.fmt.parseUnsigned(usize, s, 10);
}

fn parseU32(s: []const u8) !u32 {
    return std.fmt.parseUnsigned(u32, s, 10);
}

fn printHelp() void {
    print(
        "Usage: test-runner [--fastxml-match <str>] [--fastxml-skip <str>] [--jobs <n>] [--seed <n>]\n" ++
            "  --seed also controls deterministic test ordering in parent mode.\n",
        .{},
    );
}

fn testGroupKey(name: []const u8) []const u8 {
    const marker = ".test.";
    if (std.mem.indexOf(u8, name, marker)) |idx| {
        return name[0 .. idx + marker.len];
    }
    return name;
}

const TestInfo = struct {
    name: []const u8,
};

const Status = enum {
    pass,
    fail,
    skip,
    leak,
    crash,
};

const Summary = struct {
    pass: usize = 0,
    fail: usize = 0,
    skip: usize = 0,
    leak: usize = 0,
    crash: usize = 0,
};

const Dashboard = struct {
    running: []?[]const u8,
    rendered_lines: usize = 0,
};

fn noteStatus(summary: *Summary, status: Status) void {
    switch (status) {
        .pass => summary.pass += 1,
        .fail => summary.fail += 1,
        .skip => summary.skip += 1,
        .leak => summary.leak += 1,
        .crash => summary.crash += 1,
    }
}

fn printRunnerError(name: []const u8, err: anyerror) void {
    print("\n== TEST {s} ==\nrunner error: {s}\n", .{ name, @errorName(err) });
}

fn runAllTests(
    gpa: std.mem.Allocator,
    io: std.Io,
    argv0: []const u8,
    filter: ?[]const u8,
    exclude_filters: []const []const u8,
    jobs: ?usize,
    seed: ?u32,
) !void {
    var tests: std.ArrayList(TestInfo) = .empty;
    defer tests.deinit(gpa);

    for (builtin.test_functions) |t| {
        if (filter) |f| {
            if (std.mem.indexOf(u8, t.name, f) == null) continue;
        }
        var excluded = false;
        for (exclude_filters) |f| {
            if (std.mem.indexOf(u8, t.name, f) != null) {
                excluded = true;
                break;
            }
        }
        if (excluded) continue;

        try tests.append(gpa, .{ .name = t.name });
    }

    if (tests.items.len == 0) {
        print("no tests selected\n", .{});
        return;
    }

    std.mem.sort(TestInfo, tests.items, {}, struct {
        fn lessThan(_: void, a: TestInfo, b: TestInfo) bool {
            const ak = testGroupKey(a.name);
            const bk = testGroupKey(b.name);
            if (std.mem.eql(u8, ak, bk)) return std.mem.lessThan(u8, a.name, b.name);
            return std.mem.lessThan(u8, ak, bk);
        }
    }.lessThan);

    const cpu_count = try std.Thread.getCpuCount();
    const job_cap = jobs orelse @min(default_job_cap, @max(@as(usize, 1), cpu_count));
    var dashboard = Dashboard{
        .running = try gpa.alloc(?[]const u8, job_cap),
    };
    defer gpa.free(dashboard.running);
    @memset(dashboard.running, null);

    var next_index: usize = 0;
    var summary: Summary = .{};

    while (next_index < tests.items.len) {
        const width = @min(job_cap, tests.items.len - next_index);
        for (dashboard.running[0..width], 0..) |*slot, idx| {
            slot.* = tests.items[next_index + idx].name;
        }
        try renderDashboard(io, &dashboard, summary, tests.items.len);

        for (dashboard.running[0..width], 0..) |*slot, idx| {
            const name = slot.* orelse unreachable;
            const status = runSingleTestCollect(gpa, io, argv0, name, seed) catch |err| blk: {
                printRunnerError(name, err);
                break :blk .crash;
            };
            slot.* = null;
            noteStatus(&summary, status);
            try renderDashboard(io, &dashboard, summary, tests.items.len);
            _ = idx;
        }
        next_index += width;
    }

    try clearDashboard(io, &dashboard);
    print(
        "pass={d} fail={d} skip={d} leak={d} crash={d}\n",
        .{ summary.pass, summary.fail, summary.skip, summary.leak, summary.crash },
    );

    if (summary.fail != 0 or summary.leak != 0 or summary.crash != 0) {
        return error.TestFailure;
    }
}

fn renderDashboard(io: std.Io, dashboard: *Dashboard, summary: Summary, total: usize) !void {
    try clearDashboard(io, dashboard);

    var stderr_buf: [4096]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &stderr_buf);
    const w = &stderr.interface;

    try w.print(
        "tests pass={d} fail={d} skip={d} leak={d} crash={d} total={d}\n",
        .{ summary.pass, summary.fail, summary.skip, summary.leak, summary.crash, total },
    );
    dashboard.rendered_lines = 1;

    for (dashboard.running) |slot| {
        if (slot) |name| {
            try w.print("  RUN {s}\n", .{name});
            dashboard.rendered_lines += 1;
        }
    }

    try w.flush();
}

fn clearDashboard(io: std.Io, dashboard: *Dashboard) !void {
    if (dashboard.rendered_lines == 0) return;
    var stderr_buf: [256]u8 = undefined;
    var stderr = std.Io.File.stderr().writer(io, &stderr_buf);
    const w = &stderr.interface;
    var i: usize = 0;
    while (i < dashboard.rendered_lines) : (i += 1) {
        try w.writeAll("\x1b[2K\r");
        if (i + 1 < dashboard.rendered_lines) try w.writeAll("\x1b[1A");
    }
    try w.flush();
    dashboard.rendered_lines = 0;
}

fn runSingleTestCollect(
    gpa: std.mem.Allocator,
    io: std.Io,
    argv0: []const u8,
    name: []const u8,
    seed: ?u32,
) !Status {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(gpa);

    try argv.appendSlice(gpa, &.{ argv0, "--fastxml-run-test", name });
    if (seed) |s| {
        const seed_arg = try std.fmt.allocPrint(gpa, "{d}", .{s});
        defer gpa.free(seed_arg);
        try argv.appendSlice(gpa, &.{ "--seed", seed_arg });
    }

    const res = try std.process.run(gpa, io, .{
        .argv = argv.items,
        .stdout_limit = .limited(8 * 1024 * 1024),
        .stderr_limit = .limited(8 * 1024 * 1024),
        .reserve_amount = 16 * 1024,
    });
    defer gpa.free(res.stdout);
    defer gpa.free(res.stderr);

    return switch (res.term) {
        .exited => |code| switch (code) {
            0 => .pass,
            2 => .skip,
            3 => .leak,
            else => blk: {
                if (res.stderr.len != 0) print("\n== TEST {s} ==\n{s}\n", .{ name, res.stderr });
                break :blk .fail;
            },
        },
        else => .crash,
    };
}

fn runSingleTest(name: []const u8, seed: ?u32) u8 {
    _ = seed;
    for (builtin.test_functions) |t| {
        if (!std.mem.eql(u8, t.name, name)) continue;
        t.func() catch |err| {
            print("FAIL {s}: {s}\n", .{ name, @errorName(err) });
            return 1;
        };
        print("PASS {s}\n", .{name});
        return 0;
    }
    print("missing test: {s}\n", .{name});
    return 1;
}
