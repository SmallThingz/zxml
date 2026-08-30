const std = @import("std");

const IntLen = enum {
    u16,
    u32,
    u64,
    usize,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const intlen = b.option(IntLen, "intlen", "Integer width used for DOM spans and node indexes") orelse .u32;

    const config_options = b.addOptions();
    config_options.addOption(IntLen, "intlen", intlen);

    const mod = b.addModule("zxml", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    // Mirror htmlparser-style config injection so index-width selection stays a
    // build-time constant all the way into the parser types.
    mod.addOptions("config", config_options);

    const bench_exe = b.addExecutable(.{
        .name = "zxml-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
    });

    const ours_runner_exe = b.addExecutable(.{
        .name = "ours_runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/runners/ours_runner.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
    });

    const tools_exe = b.addExecutable(.{
        .name = "zxml-tools",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/scripts.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
    });

    b.installArtifact(bench_exe);
    b.installArtifact(ours_runner_exe);
    b.installArtifact(tools_exe);

    const bench_step = b.step("bench", "Run local zxml benchmark");
    const tools_step = b.step("tools", "Run zxml-tools utility");
    const bench_compare_step = b.step("bench-compare", "Run parser comparison benchmarks");
    const conformance_step = b.step("conformance", "Run XML conformance suites");

    const bench_cmd = b.addRunArtifact(bench_exe);
    const tools_cmd = b.addRunArtifact(tools_exe);

    const compare_cmd = b.addRunArtifact(tools_exe);
    compare_cmd.addArg("run-benchmarks");
    const conformance_cmd = b.addRunArtifact(tools_exe);
    conformance_cmd.addArg("run-conformance");

    bench_step.dependOn(&bench_cmd.step);
    tools_step.dependOn(&tools_cmd.step);
    bench_compare_step.dependOn(&compare_cmd.step);
    conformance_step.dependOn(&conformance_cmd.step);

    bench_cmd.step.dependOn(b.getInstallStep());
    tools_cmd.step.dependOn(b.getInstallStep());
    compare_cmd.step.dependOn(b.getInstallStep());
    conformance_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        bench_cmd.addArgs(args);
        tools_cmd.addArgs(args);
        compare_cmd.addArgs(args);
        conformance_cmd.addArgs(args);
    } else {
        bench_cmd.addArg("bench/smoke.xml");
        bench_cmd.addArg("1");
        tools_cmd.addArg("--help");
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    if (b.args) |args| {
        run_mod_tests.addArgs(args);
    }

    const example_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/basic_parse.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_example_tests = b.addRunArtifact(example_tests);
    if (b.args) |args| run_example_tests.addArgs(args);

    const bench_runner_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/runners/run_parse.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_bench_runner_tests = b.addRunArtifact(bench_runner_tests);
    if (b.args) |args| run_bench_runner_tests.addArgs(args);

    const tools_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/scripts.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_tools_tests = b.addRunArtifact(tools_tests);
    if (b.args) |args| run_tools_tests.addArgs(args);

    const tools_common_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/common.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_tools_common_tests = b.addRunArtifact(tools_common_tests);
    if (b.args) |args| run_tools_common_tests.addArgs(args);

    const conformance_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/conformance.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_conformance_tests = b.addRunArtifact(conformance_tests);
    if (b.args) |args| run_conformance_tests.addArgs(args);

    const public_api_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/public_api.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zxml", .module = mod },
            },
        }),
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_public_api_tests = b.addRunArtifact(public_api_tests);
    if (b.args) |args| run_public_api_tests.addArgs(args);
    const public_api_step = b.step("test-public-api", "Compile and execute every public zxml API function");
    public_api_step.dependOn(&run_public_api_tests.step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_example_tests.step);
    test_step.dependOn(&run_bench_runner_tests.step);
    test_step.dependOn(&run_tools_tests.step);
    test_step.dependOn(&run_tools_common_tests.step);
    test_step.dependOn(&run_conformance_tests.step);
    test_step.dependOn(&run_public_api_tests.step);
}
