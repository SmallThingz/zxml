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

    const mod = b.addModule("fastxml", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("config", config_options);

    const bench_exe = b.addExecutable(.{
        .name = "fastxml-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fastxml", .module = mod },
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
                .{ .name = "fastxml", .module = mod },
            },
        }),
    });

    const tools_exe = b.addExecutable(.{
        .name = "fastxml-tools",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/scripts.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fastxml", .module = mod },
            },
        }),
    });

    b.installArtifact(bench_exe);
    b.installArtifact(ours_runner_exe);
    b.installArtifact(tools_exe);

    const bench_step = b.step("bench", "Run local fastxml benchmark");
    const tools_step = b.step("tools", "Run fastxml-tools utility");
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
        bench_cmd.addArg("bench/fixtures/note.xml");
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

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
