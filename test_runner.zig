const std = @import("std");
const builtin = @import("builtin");

pub const panic = std.debug.FullPanic(panicHandler);

var is_child_mode: bool = false;
const default_job_cap: usize = 16;

fn print(comptime fmt: []const u8, args: anytype) void {
    std.debug.print(fmt, args);
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

pub fn main(init: std.process.Init) !void {
    const threaded = std.Io.Threaded.init(init.gpa, .{
        .argv0 = .init(init.minimal.args),
        .environ = init.minimal.environ,
    });
    std.testing.io_instance = threaded;
    defer std.testing.io_instance.deinit();
    std.testing.environ = init.minimal.environ;

    var arg_it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer arg_it.deinit();

    const argv0_z = arg_it.next() orelse "test-runner";
    const argv0 = try init.gpa.dupe(u8, argv0_z[0..argv0_z.len]);
    defer init.gpa.free(argv0);

    var child_test_name: ?[]const u8 = null;
    var filter: ?[]const u8 = null;
    var exclude_filters: std.ArrayList([]const u8) = .empty;
    defer exclude_filters.deinit(init.gpa);
    var jobs: ?usize = null;
    var seed: ?u32 = null;

    while (arg_it.next()) |arg_z| {
        const arg = arg_z[0..arg_z.len];
        if (std.mem.eql(u8, arg, "--run-test")) {
            const name_z = arg_it.next() orelse return error.MissingTestName;
            child_test_name = try init.gpa.dupe(u8, name_z[0..name_z.len]);
        } else if (std.mem.eql(u8, arg, "--test-filter")) {
            const f_z = arg_it.next() orelse return error.MissingFilter;
            filter = try init.gpa.dupe(u8, f_z[0..f_z.len]);
        } else if (std.mem.eql(u8, arg, "--test-skip")) {
            const f_z = arg_it.next() orelse return error.MissingFilter;
            try exclude_filters.append(init.gpa, try init.gpa.dupe(u8, f_z[0..f_z.len]));
        } else if (std.mem.eql(u8, arg, "--jobs")) {
            const j_z = arg_it.next() orelse return error.MissingJobs;
            jobs = try parseUsize(j_z[0..j_z.len]);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            const s_z = arg_it.next() orelse return error.MissingSeed;
            seed = try parseU32(s_z[0..s_z.len]);
        } else if (std.mem.eql(u8, arg, "--help")) {
            printHelp();
            return;
        } else {
            // Ignore unknown args to stay compatible with Zig's test flags.
        }
    }

    defer if (child_test_name) |name| init.gpa.free(name);
    defer if (filter) |f| init.gpa.free(f);
    defer for (exclude_filters.items) |f| init.gpa.free(f);

    if (child_test_name) |name| {
        is_child_mode = true;
        runSingleTest(name, seed);
        return;
    }

    try runAllTests(init.gpa, init.io, argv0, filter, exclude_filters.items, jobs, seed);
}

fn panicHandler(msg: []const u8, first_trace_addr: ?usize) noreturn {
    if (is_child_mode) {
        print("{s}\n", .{msg});
        std.process.exit(1);
    }
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
        "Usage: test-runner [--test-filter <str>] [--test-skip <str>] [--jobs <n>] [--seed <n>]\n" ++
            "  --seed also controls deterministic test ordering in parent mode.\n",
        .{},
    );
}

fn testGroupKey(name: []const u8) []const u8 {
    // Keep tests from the same module adjacent so parallel scheduling does not
    // make the live dashboard jump between unrelated groups every line.
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
    /// One slot per worker thread so the parent process can redraw the live
    /// "currently running" view without interleaving worker output.
    running: []?[]const u8,
    /// Number of lines emitted by the last dashboard render so they can be
    /// cleared before printing result lines or the next dashboard frame.
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
        print("0 tests selected\n", .{});
        return;
    }

    const GroupBucket = struct {
        key: []const u8,
        items: std.ArrayList(TestInfo) = .empty,
        next: usize = 0,
    };

    var buckets: std.ArrayList(GroupBucket) = .empty;
    defer {
        for (buckets.items) |*b| b.items.deinit(gpa);
        buckets.deinit(gpa);
    }

    for (tests.items) |t| {
        const key = testGroupKey(t.name);
        var found: ?usize = null;
        for (buckets.items, 0..) |b, bi| {
            if (std.mem.eql(u8, b.key, key)) {
                found = bi;
                break;
            }
        }
        if (found == null) {
            try buckets.append(gpa, .{ .key = key });
            found = buckets.items.len - 1;
        }
        try buckets.items[found.?].items.append(gpa, t);
    }

    if (seed) |s| {
        var prng = std.Random.DefaultPrng.init(@as(u64, s));
        var random = prng.random();
        shuffleSlice(GroupBucket, &random, buckets.items);
        for (buckets.items) |*bucket| {
            shuffleSlice(TestInfo, &random, bucket.items.items);
        }
    }

    var reordered: std.ArrayList(TestInfo) = .empty;
    defer reordered.deinit(gpa);
    try reordered.ensureTotalCapacity(gpa, tests.items.len);

    var remaining = tests.items.len;
    while (remaining != 0) {
        for (buckets.items) |*bucket| {
            if (bucket.next >= bucket.items.items.len) continue;
            try reordered.append(gpa, bucket.items.items[bucket.next]);
            bucket.next += 1;
            remaining -= 1;
        }
    }

    @memcpy(tests.items, reordered.items);

    const cpu_count = std.Thread.getCpuCount() catch 1;
    var job_count = jobs orelse @min(cpu_count, default_job_cap);
    if (job_count == 0) job_count = 1;
    if (job_count > tests.items.len) job_count = tests.items.len;

    var next_index: std.atomic.Value(usize) = .init(0);
    var summary: Summary = .{};
    var print_mutex: std.Io.Mutex = .init;
    var count_mutex: std.Io.Mutex = .init;
    const running = try gpa.alloc(?[]const u8, job_count);
    defer gpa.free(running);
    @memset(running, null);
    var dashboard: Dashboard = .{ .running = running };

    var ctx = WorkerCtx{
        .gpa = gpa,
        .io = io,
        .argv0 = argv0,
        .tests = tests.items,
        .seed = seed,
        .next_index = &next_index,
        .summary = &summary,
        .print_mutex = &print_mutex,
        .count_mutex = &count_mutex,
        .dashboard = &dashboard,
    };

    if (builtin.single_threaded or job_count == 1) {
        worker(&ctx, 0);
    } else {
        const threads = try gpa.alloc(std.Thread, job_count);
        defer gpa.free(threads);
        for (threads, 0..) |*t, i| {
            t.* = try std.Thread.spawn(.{}, worker, .{ &ctx, i });
        }
        for (threads) |t| t.join();
    }

    print_mutex.lockUncancelable(io);
    clearDashboardLocked(&ctx);
    print_mutex.unlock(io);

    print(
        "\npass: {d}  fail: {d}  skip: {d}  leak: {d}  crash: {d}\n",
        .{ summary.pass, summary.fail, summary.skip, summary.leak, summary.crash },
    );

    if (summary.fail != 0 or summary.crash != 0 or summary.leak != 0) {
        std.process.exit(1);
    }
}

fn shuffleSlice(comptime T: type, random: *std.Random, items: []T) void {
    if (items.len <= 1) return;
    var i: usize = items.len - 1;
    while (i != 0) {
        const j = random.uintLessThan(usize, i + 1);
        std.mem.swap(T, &items[i], &items[j]);
        i -= 1;
    }
}

const WorkerCtx = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    argv0: []const u8,
    tests: []const TestInfo,
    seed: ?u32,
    next_index: *std.atomic.Value(usize),
    summary: *Summary,
    print_mutex: *std.Io.Mutex,
    count_mutex: *std.Io.Mutex,
    /// Shared dashboard state updated by each worker while its child process
    /// is running.
    dashboard: *Dashboard,
};

fn clearDashboardLocked(ctx: *WorkerCtx) void {
    if (ctx.dashboard.rendered_lines == 0) return;
    print("\x1b[{d}F", .{ctx.dashboard.rendered_lines});
    var i: usize = 0;
    while (i < ctx.dashboard.rendered_lines) : (i += 1) {
        print("\x1b[2K\n", .{});
    }
    print("\x1b[{d}F", .{ctx.dashboard.rendered_lines});
    ctx.dashboard.rendered_lines = 0;
}

fn renderDashboardLocked(ctx: *WorkerCtx) void {
    clearDashboardLocked(ctx);

    var rendered: usize = 0;
    for (ctx.dashboard.running) |name_opt| {
        if (name_opt) |name| {
            print("\x1b[33mrunning\x1b[0m {s}\n", .{name});
            rendered += 1;
        }
    }
    ctx.dashboard.rendered_lines = rendered;
}

fn worker(ctx: *WorkerCtx, slot: usize) void {
    while (true) {
        const idx = ctx.next_index.fetchAdd(1, .seq_cst);
        if (idx >= ctx.tests.len) break;

        const test_name = ctx.tests[idx].name;

        ctx.print_mutex.lockUncancelable(ctx.io);
        ctx.dashboard.running[slot] = test_name;
        renderDashboardLocked(ctx);
        ctx.print_mutex.unlock(ctx.io);

        const result = runChildTest(ctx, test_name) catch |err| {
            ctx.print_mutex.lockUncancelable(ctx.io);
            defer ctx.print_mutex.unlock(ctx.io);
            clearDashboardLocked(ctx);
            ctx.dashboard.running[slot] = null;
            printRunnerError(test_name, err);
            renderDashboardLocked(ctx);
            ctx.count_mutex.lockUncancelable(ctx.io);
            noteStatus(ctx.summary, .fail);
            ctx.count_mutex.unlock(ctx.io);
            continue;
        };

        ctx.print_mutex.lockUncancelable(ctx.io);
        defer ctx.print_mutex.unlock(ctx.io);
        defer deinitChildResult(ctx.gpa, result);
        clearDashboardLocked(ctx);
        ctx.dashboard.running[slot] = null;
        printTestOutput(test_name, result);
        renderDashboardLocked(ctx);

        ctx.count_mutex.lockUncancelable(ctx.io);
        noteStatus(ctx.summary, result.status);
        ctx.count_mutex.unlock(ctx.io);
    }
}

const ChildResult = struct {
    status: Status,
    term: std.process.Child.Term,
    stdout: []u8,
    stderr: []u8,
};

fn runChildTest(ctx: *WorkerCtx, test_name: []const u8) !ChildResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(ctx.gpa);

    try argv.append(ctx.gpa, ctx.argv0);
    try argv.append(ctx.gpa, "--run-test");
    try argv.append(ctx.gpa, test_name);

    var seed_buf: ?[]u8 = null;
    if (ctx.seed) |s| {
        const seed_str = try std.fmt.allocPrint(ctx.gpa, "{d}", .{s});
        seed_buf = seed_str;
        try argv.append(ctx.gpa, "--seed");
        try argv.append(ctx.gpa, seed_str);
    }
    defer if (seed_buf) |b| ctx.gpa.free(b);

    const run_result = try std.process.run(ctx.gpa, ctx.io, .{
        .argv = argv.items,
        .stdout_limit = .limited(256 * 1024),
        .stderr_limit = .limited(256 * 1024),
        .reserve_amount = 16 * 1024,
    });

    return .{
        .status = classifyStatus(run_result.term),
        .term = run_result.term,
        .stdout = run_result.stdout,
        .stderr = run_result.stderr,
    };
}

fn classifyStatus(term: std.process.Child.Term) Status {
    switch (term) {
        .exited => |code| return switch (code) {
            0 => .pass,
            2 => .skip,
            3 => .leak,
            else => .fail,
        },
        .signal, .stopped, .unknown => return .crash,
    }
}

fn printTestOutput(name: []const u8, res: ChildResult) void {
    const color = switch (res.status) {
        .pass => "\x1b[32m",
        .skip => "\x1b[94m",
        else => "\x1b[31m",
    };
    const label = switch (res.status) {
        .pass => "ok",
        .skip => "skip",
        .leak => "leak",
        .crash => "crash",
        .fail => "error",
    };

    print("{s}{s}\x1b[0m {s}", .{ color, label, name });

    switch (res.term) {
        .exited => |code| if (code != 0) print(" | exit {d}", .{code}),
        .signal => |sig| print(" | signal {d} ({s})", .{ @intFromEnum(sig), @tagName(sig) }),
        .stopped => |code| print(" | stopped {d}", .{code}),
        .unknown => |code| print(" | unknown {d}", .{code}),
    }

    print("\n", .{});
    if (res.stderr.len != 0 and res.status != .pass and res.status != .skip) {
        print("stderr:\n{s}", .{res.stderr});
        if (res.stderr[res.stderr.len - 1] != '\n') print("\n", .{});
    }
    if (res.stdout.len != 0 and res.status != .pass and res.status != .skip) {
        print("stdout:\n{s}", .{res.stdout});
        if (res.stdout[res.stdout.len - 1] != '\n') print("\n", .{});
    }
}

fn deinitChildResult(gpa: std.mem.Allocator, res: ChildResult) void {
    gpa.free(res.stdout);
    gpa.free(res.stderr);
}

fn runSingleTest(name: []const u8, seed: ?u32) void {
    if (seed) |s| std.testing.random_seed = s;

    const test_fn = findTest(name) orelse {
        print("unknown test: {s}\n", .{name});
        std.process.exit(1);
    };

    std.testing.allocator_instance = .{};
    const result = test_fn.func();
    const leak_status = std.testing.allocator_instance.deinit();

    if (leak_status == .leak) {
        print("memory leak\n", .{});
        std.process.exit(3);
    }

    if (result) |_| {
        std.process.exit(0);
    } else |err| switch (err) {
        error.SkipZigTest => std.process.exit(2),
        else => {
            print("{s}\n", .{@errorName(err)});
            std.process.exit(1);
        },
    }
}

const TestFn = std.meta.Elem(@TypeOf(builtin.test_functions));

fn findTest(name: []const u8) ?TestFn {
    for (builtin.test_functions) |t| {
        if (std.mem.eql(u8, t.name, name)) return t;
    }
    return null;
}
