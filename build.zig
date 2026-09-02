const std = @import("std");

const IntLen = enum {
    u16,
    u32,
    u64,
    usize,
};

/// Configures build artifacts, helper steps, and test/check pipelines.
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

    const stream_bench_exe = b.addExecutable(.{
        .name = "zxml-stream-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/stream_bench.zig"),
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

    const install_bench = b.addInstallArtifact(bench_exe, .{});
    const install_stream_bench = b.addInstallArtifact(stream_bench_exe, .{});
    b.getInstallStep().dependOn(&install_bench.step);
    b.getInstallStep().dependOn(&install_stream_bench.step);
    const bench_only_step = b.step("bench-only", "Build benchmark binaries only");
    bench_only_step.dependOn(&install_bench.step);
    bench_only_step.dependOn(&install_stream_bench.step);
    b.installArtifact(tools_exe);

    const tools_step = b.step("tools", "Run zxml-tools utility");
    const bench_compare_step = b.step("bench-compare", "Benchmark against external parser implementations");
    const conformance_step = b.step("conformance", "Run XML conformance suites");

    const tools_cmd = b.addRunArtifact(tools_exe);

    const setup_parsers_cmd = b.addRunArtifact(tools_exe);
    setup_parsers_cmd.addArg("setup-parsers");

    const setup_fixtures_cmd = b.addRunArtifact(tools_exe);
    setup_fixtures_cmd.addArg("setup-fixtures");
    setup_fixtures_cmd.step.dependOn(&setup_parsers_cmd.step);

    const compare_cmd = b.addRunArtifact(tools_exe);
    compare_cmd.addArg("run-benchmarks");
    compare_cmd.step.dependOn(&setup_fixtures_cmd.step);

    const conformance_cmd = b.addRunArtifact(tools_exe);
    conformance_cmd.addArg("run-conformance");

    tools_step.dependOn(&tools_cmd.step);
    bench_compare_step.dependOn(&compare_cmd.step);
    conformance_step.dependOn(&conformance_cmd.step);

    tools_cmd.step.dependOn(b.getInstallStep());
    setup_parsers_cmd.step.dependOn(b.getInstallStep());
    setup_fixtures_cmd.step.dependOn(b.getInstallStep());
    compare_cmd.step.dependOn(b.getInstallStep());
    conformance_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        tools_cmd.addArgs(args);
        compare_cmd.addArgs(args);
        conformance_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

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

    const bench_tests = b.addTest(.{
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
    const run_bench_tests = b.addRunArtifact(bench_tests);

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

    const tools_common_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/common.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_tools_common_tests = b.addRunArtifact(tools_common_tests);

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
    const public_api_step = b.step("test-public-api", "Run exhaustive consumer-facing public API tests");
    public_api_step.dependOn(&run_public_api_tests.step);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_example_tests.step);
    test_step.dependOn(&run_bench_tests.step);
    test_step.dependOn(&run_tools_tests.step);
    test_step.dependOn(&run_tools_common_tests.step);
    test_step.dependOn(&run_conformance_tests.step);
    test_step.dependOn(&run_public_api_tests.step);
}
