const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("fastxml", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "fastxml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fastxml", .module = mod },
            },
        }),
    });

    const bench_exe = b.addExecutable(.{
        .name = "fastxml-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bench/bench.zig"),
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
            .root_source_file = b.path("src/tools/scripts.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fastxml", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);
    b.installArtifact(bench_exe);
    b.installArtifact(tools_exe);

    const run_step = b.step("run", "Run demo app");
    const bench_step = b.step("bench", "Run local fastxml benchmark");
    const tools_step = b.step("tools", "Run fastxml-tools utility");
    const bench_compare_step = b.step("bench-compare", "Run parser comparison benchmarks");
    const conformance_step = b.step("conformance", "Run XML conformance suites");
    const compliance_step = b.step("compliance", "Alias for `zig build conformance`");

    const run_cmd = b.addRunArtifact(exe);
    const bench_cmd = b.addRunArtifact(bench_exe);
    const tools_cmd = b.addRunArtifact(tools_exe);

    const compare_cmd = b.addRunArtifact(tools_exe);
    compare_cmd.addArg("run-benchmarks");
    const conformance_cmd = b.addRunArtifact(tools_exe);
    conformance_cmd.addArg("run-conformance");

    run_step.dependOn(&run_cmd.step);
    bench_step.dependOn(&bench_cmd.step);
    tools_step.dependOn(&tools_cmd.step);
    bench_compare_step.dependOn(&compare_cmd.step);
    conformance_step.dependOn(&conformance_cmd.step);
    compliance_step.dependOn(&conformance_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    bench_cmd.step.dependOn(b.getInstallStep());
    tools_cmd.step.dependOn(b.getInstallStep());
    compare_cmd.step.dependOn(b.getInstallStep());
    conformance_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
        bench_cmd.addArgs(args);
        tools_cmd.addArgs(args);
        compare_cmd.addArgs(args);
        conformance_cmd.addArgs(args);
    }

    const test_mod = b.createModule(.{
        .root_source_file = b.path("test_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const mod_tests = b.addTest(.{
        .root_module = test_mod,
        .test_runner = .{ .path = b.path("test_runner.zig"), .mode = .simple },
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    if (b.args) |args| {
        run_mod_tests.addArgs(args);
    }

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
