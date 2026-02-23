const std = @import("std");
const common = @import("common.zig");
const conformance = @import("conformance.zig");

const REPO_ROOT = ".";
const BUILD_DIR = "bench/build";
const BIN_DIR = "bench/build/bin";
const RESULTS_DIR = "bench/results";
const FIXTURES_DIR = "bench/fixtures";
const PARSERS_DIR = "bench/parsers";

const repeats: usize = 5;

const parse_parsers = [_][]const u8{
    "ours-strict",
    "ours-turbo",
    "strlen",
    "libxml2",
    "yxml",
    "pugixml",
    "rapidxml",
};

const FixtureCase = struct {
    name: []const u8,
    iterations: usize,
    is_real: bool,
};

const Profile = struct {
    name: []const u8,
    fixtures: []const FixtureCase,
};

const quick_fixtures = [_]FixtureCase{
    .{ .name = "note.xml", .iterations = 120, .is_real = true },
    .{ .name = "sitemaps.xml", .iterations = 120, .is_real = true },
    .{ .name = "plant_catalog.xml", .iterations = 50, .is_real = true },
    .{ .name = "cd_catalog.xml", .iterations = 80, .is_real = true },
    .{ .name = "synthetic_flat_attrs.xml", .iterations = 120, .is_real = false },
    .{ .name = "synthetic_deep_tree.xml", .iterations = 150, .is_real = false },
    .{ .name = "synthetic_entities.xml", .iterations = 100, .is_real = false },
    .{ .name = "synthetic_cdata_mix.xml", .iterations = 100, .is_real = false },
};

const stable_fixtures = [_]FixtureCase{
    .{ .name = "note.xml", .iterations = 300, .is_real = true },
    .{ .name = "sitemaps.xml", .iterations = 300, .is_real = true },
    .{ .name = "plant_catalog.xml", .iterations = 140, .is_real = true },
    .{ .name = "cd_catalog.xml", .iterations = 200, .is_real = true },
    .{ .name = "synthetic_flat_attrs.xml", .iterations = 280, .is_real = false },
    .{ .name = "synthetic_deep_tree.xml", .iterations = 320, .is_real = false },
    .{ .name = "synthetic_entities.xml", .iterations = 240, .is_real = false },
    .{ .name = "synthetic_cdata_mix.xml", .iterations = 240, .is_real = false },
};

const ParseResult = struct {
    parser: []const u8,
    fixture: []const u8,
    is_real: bool,
    iterations: usize,
    samples_ns: []u64,
    median_ns: u64,
    throughput_mb_s: f64,
};

const GateRow = struct {
    fixture: []const u8,
    is_real: bool,
    ours_turbo_mb_s: f64,
    strlen_mb_s: f64,
    libxml2_mb_s: f64,
    yxml_mb_s: f64,
    pugixml_mb_s: f64,
    rapidxml_mb_s: f64,
    strlen_ratio: f64,
    strlen_threshold: f64,
    pass_sota: bool,
    pass_strlen: bool,
    pass: bool,
};

fn getProfile(name: []const u8) !Profile {
    if (std.mem.eql(u8, name, "quick")) return .{ .name = "quick", .fixtures = &quick_fixtures };
    if (std.mem.eql(u8, name, "stable")) return .{ .name = "stable", .fixtures = &stable_fixtures };
    return error.InvalidProfile;
}

fn pathExists(path: []const u8) bool {
    return common.fileExists(path);
}

fn setupParsers(alloc: std.mem.Allocator) !void {
    try common.ensureDir(PARSERS_DIR);

    const pugixml_git = PARSERS_DIR ++ "/pugixml/.git";
    if (!pathExists(pugixml_git)) {
        const argv = [_][]const u8{ "git", "clone", "--depth", "1", "https://github.com/zeux/pugixml.git", PARSERS_DIR ++ "/pugixml" };
        try common.runInherit(alloc, &argv, REPO_ROOT);
    } else {
        std.debug.print("already present: pugixml\n", .{});
    }

    try common.ensureDir(PARSERS_DIR ++ "/rapidxml");
    const rapid_files = [_][]const u8{
        "rapidxml.hpp",
        "rapidxml_iterators.hpp",
        "rapidxml_print.hpp",
        "rapidxml_utils.hpp",
        "license.txt",
    };
    for (rapid_files) |f| {
        const src = try std.fmt.allocPrint(alloc, "rapidxml-1.13/{s}", .{f});
        defer alloc.free(src);
        const dst = try std.fmt.allocPrint(alloc, PARSERS_DIR ++ "/rapidxml/{s}", .{f});
        defer alloc.free(dst);
        if (pathExists(dst)) continue;
        const cp = [_][]const u8{ "cp", src, dst };
        try common.runInherit(alloc, &cp, REPO_ROOT);
    }

    try common.ensureDir(PARSERS_DIR ++ "/yxml");
    const yxml_files = [_][]const u8{ "yxml.c", "yxml.h" };
    for (yxml_files) |f| {
        const dst = try std.fmt.allocPrint(alloc, PARSERS_DIR ++ "/yxml/{s}", .{f});
        defer alloc.free(dst);
        if (pathExists(dst)) continue;

        const url = try std.fmt.allocPrint(alloc, "https://g.blicky.net/yxml.git/plain/{s}", .{f});
        defer alloc.free(url);
        const argv = [_][]const u8{ "curl", "-L", "--fail", "--retry", "2", "--retry-delay", "1", url, "-o", dst };
        try common.runInherit(alloc, &argv, REPO_ROOT);
    }

    std.debug.print("parsers ready\n", .{});
}

fn writeSyntheticFixtures() !void {
    try writeFlatAttrs(FIXTURES_DIR ++ "/synthetic_flat_attrs.xml");
    try writeDeepTree(FIXTURES_DIR ++ "/synthetic_deep_tree.xml");
    try writeEntities(FIXTURES_DIR ++ "/synthetic_entities.xml");
    try writeCdataMix(FIXTURES_DIR ++ "/synthetic_cdata_mix.xml");
}

fn writeFlatAttrs(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(&out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<rows>");
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        try out.print("<row id='{d}' a='x' b='y' c='z' d='w' e='q' f='n' g='m' h='k' i='j' j='t'/>", .{i});
    }
    try out.writeAll("</rows>");
    try out.flush();
}

fn writeDeepTree(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(&out_buf);
    const out = &out_writer.interface;
    var depth: usize = 0;
    while (depth < 128) : (depth += 1) {
        try out.print("<n d='{d}'>", .{depth});
    }
    try out.writeAll("leaf");
    while (depth > 0) {
        depth -= 1;
        try out.writeAll("</n>");
    }
    try out.flush();
}

fn writeEntities(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(&out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<root>");
    var i: usize = 0;
    while (i < 9000) : (i += 1) {
        try out.writeAll("<item v='&amp;&lt;&gt;&quot;&apos;'>&#65;&#x42;&amp;ok&lt;test&gt;</item>");
    }
    try out.writeAll("</root>");
    try out.flush();
}

fn writeCdataMix(path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(&out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<?xml version='1.0'?><!DOCTYPE doc [<!ELEMENT doc ANY>]><doc>");
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        try out.print("<!--c{d}--><![CDATA[data<{d}>]]><?pi value='{d}'?><x>{d}</x>", .{ i, i, i, i });
    }
    try out.writeAll("</doc>");
    try out.flush();
}

fn setupFixtures(alloc: std.mem.Allocator, refresh: bool) !void {
    try common.ensureDir(FIXTURES_DIR);

    const targets = [_]struct { url: []const u8, out: []const u8 }{
        .{ .url = "https://www.w3schools.com/xml/note.xml", .out = "note.xml" },
        .{ .url = "https://www.sitemaps.org/sitemap.xml", .out = "sitemaps.xml" },
        .{ .url = "https://www.w3schools.com/xml/plant_catalog.xml", .out = "plant_catalog.xml" },
        .{ .url = "https://www.w3schools.com/xml/cd_catalog.xml", .out = "cd_catalog.xml" },
    };

    for (targets) |item| {
        const target = try std.fmt.allocPrint(alloc, FIXTURES_DIR ++ "/{s}", .{item.out});
        defer alloc.free(target);

        if (!refresh) {
            const st = std.fs.cwd().statFile(target) catch null;
            if (st != null and st.?.size > 0) {
                std.debug.print("cached: {s}\n", .{item.out});
                continue;
            }
        }

        const argv = [_][]const u8{
            "curl",
            "-L",
            "--fail",
            "--retry",
            "2",
            "--retry-delay",
            "1",
            "-A",
            "fastxml-bench/1.0",
            item.url,
            "-o",
            target,
        };
        try common.runInherit(alloc, &argv, REPO_ROOT);
    }

    try writeSyntheticFixtures();
    std.debug.print("fixtures ready\n", .{});
}

fn ensureExternalParsersBuilt(alloc: std.mem.Allocator) !void {
    if (!pathExists(PARSERS_DIR ++ "/pugixml/CMakeLists.txt")) {
        try setupParsers(alloc);
    }
}

fn appendPkgConfigArgs(alloc: std.mem.Allocator, list: *std.ArrayList([]const u8), package: []const u8) !void {
    const out = try common.runCaptureStdout(alloc, &[_][]const u8{ "pkg-config", "--cflags", "--libs", package }, REPO_ROOT);
    defer alloc.free(out);

    var it = std.mem.tokenizeAny(u8, out, " \t\n\r");
    while (it.next()) |tok| {
        try list.append(alloc, try alloc.dupe(u8, tok));
    }
}

fn freeOwnedArgs(alloc: std.mem.Allocator, args: []const []const u8) void {
    for (args) |a| alloc.free(a);
}

fn buildRunners(alloc: std.mem.Allocator) !void {
    try common.ensureDir(BUILD_DIR);
    try common.ensureDir(BIN_DIR);

    const zig_build = [_][]const u8{ "zig", "build", "-Doptimize=ReleaseFast" };
    try common.runInherit(alloc, &zig_build, REPO_ROOT);

    const ours = [_][]const u8{
        "zig",
        "build-exe",
        "-O",
        "ReleaseFast",
        "--dep",
        "fastxml",
        "-Mroot=bench/runners/ours_runner.zig",
        "-Mfastxml=src/root.zig",
        "-femit-bin=bench/build/bin/ours_runner",
    };
    try common.runInherit(alloc, &ours, REPO_ROOT);

    const strlen_cc = [_][]const u8{
        "cc",
        "-O3",
        "-fno-builtin",
        "bench/runners/strlen_runner.c",
        "-o",
        "bench/build/bin/strlen_runner",
    };
    try common.runInherit(alloc, &strlen_cc, REPO_ROOT);

    var libxml_args = std.ArrayList([]const u8).empty;
    const base_arg_count: usize = 5;
    defer {
        if (libxml_args.items.len > base_arg_count) freeOwnedArgs(alloc, libxml_args.items[base_arg_count..]);
        libxml_args.deinit(alloc);
    }
    try libxml_args.appendSlice(alloc, &.{
        "cc",
        "-O3",
        "bench/runners/libxml2_runner.c",
        "-o",
        "bench/build/bin/libxml2_runner",
    });
    try appendPkgConfigArgs(alloc, &libxml_args, "libxml-2.0");
    try common.runInherit(alloc, libxml_args.items, REPO_ROOT);

    const pugixml_cc = [_][]const u8{
        "c++",
        "-O3",
        "-std=c++17",
        "bench/runners/pugixml_runner.cpp",
        "bench/parsers/pugixml/src/pugixml.cpp",
        "-Ibench/parsers/pugixml/src",
        "-o",
        "bench/build/bin/pugixml_runner",
    };
    try common.runInherit(alloc, &pugixml_cc, REPO_ROOT);

    const rapidxml_cc = [_][]const u8{
        "c++",
        "-O3",
        "-std=c++17",
        "bench/runners/rapidxml_runner.cpp",
        "-Ibench/parsers/rapidxml",
        "-o",
        "bench/build/bin/rapidxml_runner",
    };
    try common.runInherit(alloc, &rapidxml_cc, REPO_ROOT);

    const yxml_cc = [_][]const u8{
        "cc",
        "-O3",
        "bench/runners/yxml_runner.c",
        "bench/parsers/yxml/yxml.c",
        "-Ibench/parsers/yxml",
        "-o",
        "bench/build/bin/yxml_runner",
    };
    try common.runInherit(alloc, &yxml_cc, REPO_ROOT);
}

fn runParser(alloc: std.mem.Allocator, parser_name: []const u8, fixture_path: []const u8, iterations: usize) !u64 {
    const iters = try std.fmt.allocPrint(alloc, "{d}", .{iterations});
    defer alloc.free(iters);

    var argv: [4][]const u8 = undefined;
    var argc: usize = 0;

    if (std.mem.eql(u8, parser_name, "ours-strict")) {
        argv[0] = BIN_DIR ++ "/ours_runner";
        argv[1] = "strict";
        argv[2] = fixture_path;
        argv[3] = iters;
        argc = 4;
    } else if (std.mem.eql(u8, parser_name, "ours-turbo")) {
        argv[0] = BIN_DIR ++ "/ours_runner";
        argv[1] = "turbo";
        argv[2] = fixture_path;
        argv[3] = iters;
        argc = 4;
    } else if (std.mem.eql(u8, parser_name, "strlen")) {
        argv[0] = BIN_DIR ++ "/strlen_runner";
        argv[1] = fixture_path;
        argv[2] = iters;
        argc = 3;
    } else if (std.mem.eql(u8, parser_name, "libxml2")) {
        argv[0] = BIN_DIR ++ "/libxml2_runner";
        argv[1] = fixture_path;
        argv[2] = iters;
        argc = 3;
    } else if (std.mem.eql(u8, parser_name, "yxml")) {
        argv[0] = BIN_DIR ++ "/yxml_runner";
        argv[1] = fixture_path;
        argv[2] = iters;
        argc = 3;
    } else if (std.mem.eql(u8, parser_name, "pugixml")) {
        argv[0] = BIN_DIR ++ "/pugixml_runner";
        argv[1] = fixture_path;
        argv[2] = iters;
        argc = 3;
    } else if (std.mem.eql(u8, parser_name, "rapidxml")) {
        argv[0] = BIN_DIR ++ "/rapidxml_runner";
        argv[1] = fixture_path;
        argv[2] = iters;
        argc = 3;
    } else {
        return error.UnknownParser;
    }

    const out = try common.runCaptureStdout(alloc, argv[0..argc], REPO_ROOT);
    defer alloc.free(out);
    return common.parseLastInt(out);
}

fn runParseBench(alloc: std.mem.Allocator, parser_name: []const u8, fixture: FixtureCase) !ParseResult {
    const fixture_path = try std.fmt.allocPrint(alloc, FIXTURES_DIR ++ "/{s}", .{fixture.name});
    defer alloc.free(fixture_path);

    const fixture_stat = try std.fs.cwd().statFile(fixture_path);

    const samples = try alloc.alloc(u64, repeats);
    errdefer alloc.free(samples);
    for (samples, 0..) |*s, rep| {
        _ = rep;
        s.* = try runParser(alloc, parser_name, fixture_path, fixture.iterations);
    }

    const median = try common.medianU64(alloc, samples);
    const bytes_total = @as(f64, @floatFromInt(fixture_stat.size)) * @as(f64, @floatFromInt(fixture.iterations));
    const throughput = if (median == 0) 0.0 else (bytes_total / (1024.0 * 1024.0)) / (@as(f64, @floatFromInt(median)) / 1_000_000_000.0);

    const parser_name_copy = try alloc.dupe(u8, parser_name);
    errdefer alloc.free(parser_name_copy);
    const fixture_name_copy = try alloc.dupe(u8, fixture.name);
    errdefer alloc.free(fixture_name_copy);

    return .{
        .parser = parser_name_copy,
        .fixture = fixture_name_copy,
        .is_real = fixture.is_real,
        .iterations = fixture.iterations,
        .samples_ns = samples,
        .median_ns = median,
        .throughput_mb_s = throughput,
    };
}

fn freeParseResult(alloc: std.mem.Allocator, row: *ParseResult) void {
    alloc.free(row.parser);
    alloc.free(row.fixture);
    alloc.free(row.samples_ns);
}

fn findThroughput(rows: []const ParseResult, parser_name: []const u8, fixture: []const u8) ?f64 {
    for (rows) |r| {
        if (std.mem.eql(u8, r.parser, parser_name) and std.mem.eql(u8, r.fixture, fixture)) return r.throughput_mb_s;
    }
    return null;
}

fn evaluateGateRows(alloc: std.mem.Allocator, profile: Profile, rows: []const ParseResult) ![]GateRow {
    var out = std.ArrayList(GateRow).empty;
    errdefer out.deinit(alloc);

    for (profile.fixtures) |fx| {
        const ours = findThroughput(rows, "ours-turbo", fx.name) orelse continue;
        const strlen = findThroughput(rows, "strlen", fx.name) orelse continue;
        const libxml2 = findThroughput(rows, "libxml2", fx.name) orelse continue;
        const yxml = findThroughput(rows, "yxml", fx.name) orelse continue;
        const pugixml = findThroughput(rows, "pugixml", fx.name) orelse continue;
        const rapidxml = findThroughput(rows, "rapidxml", fx.name) orelse continue;

        const threshold: f64 = if (fx.is_real) 0.35 else 0.60;
        const ratio = if (strlen == 0) 0 else ours / strlen;
        const pass_sota = ours > libxml2 and ours > yxml and ours > pugixml and ours > rapidxml;
        const pass_strlen = ratio >= threshold;

        try out.append(alloc, .{
            .fixture = try alloc.dupe(u8, fx.name),
            .is_real = fx.is_real,
            .ours_turbo_mb_s = ours,
            .strlen_mb_s = strlen,
            .libxml2_mb_s = libxml2,
            .yxml_mb_s = yxml,
            .pugixml_mb_s = pugixml,
            .rapidxml_mb_s = rapidxml,
            .strlen_ratio = ratio,
            .strlen_threshold = threshold,
            .pass_sota = pass_sota,
            .pass_strlen = pass_strlen,
            .pass = pass_sota and pass_strlen,
        });
    }

    return out.toOwnedSlice(alloc);
}

fn freeGateRows(alloc: std.mem.Allocator, rows: []GateRow) void {
    for (rows) |r| alloc.free(r.fixture);
    alloc.free(rows);
}

fn maxUsize(a: usize, b: usize) usize {
    return if (a > b) a else b;
}

fn writeRepeatedByte(writer: anytype, byte: u8, count: usize) !void {
    var i: usize = 0;
    while (i < count) : (i += 1) try writer.writeByte(byte);
}

fn writeTableBorder(writer: anytype, widths: []const usize) !void {
    try writer.writeByte('+');
    for (widths) |width| {
        try writeRepeatedByte(writer, '-', width + 2);
        try writer.writeByte('+');
    }
    try writer.writeByte('\n');
}

fn writeTableCell(writer: anytype, text: []const u8, width: usize, right_align: bool) !void {
    try writer.writeByte(' ');
    if (right_align and width > text.len) try writeRepeatedByte(writer, ' ', width - text.len);
    try writer.writeAll(text);
    if (!right_align and width > text.len) try writeRepeatedByte(writer, ' ', width - text.len);
    try writer.writeByte(' ');
}

fn writeTableRow(writer: anytype, cells: []const []const u8, widths: []const usize, right_align: []const bool) !void {
    std.debug.assert(cells.len == widths.len);
    std.debug.assert(cells.len == right_align.len);

    try writer.writeByte('|');
    var i: usize = 0;
    while (i < cells.len) : (i += 1) {
        try writeTableCell(writer, cells[i], widths[i], right_align[i]);
        try writer.writeByte('|');
    }
    try writer.writeByte('\n');
}

fn writeMarkdown(alloc: std.mem.Allocator, profile_name: []const u8, parse_results: []const ParseResult, gate_rows: []const GateRow) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(alloc);
    const w = out.writer(alloc);

    try w.print("# FastXML Benchmark Results\n\nGenerated (unix): {d}\n\nProfile: `{s}`\n\n", .{ common.nowUnix(), profile_name });

    try w.writeAll("## Parse Throughput\n\n");
    try w.writeAll("| Fixture | Parser | Throughput (MB/s) | Median Time (ms) | Iterations |\n");
    try w.writeAll("|---|---|---:|---:|---:|\n");
    for (parse_results) |r| {
        const median_ms = @as(f64, @floatFromInt(r.median_ns)) / 1_000_000.0;
        try w.print("| {s} | {s} | {d:.2} | {d:.2} | {d} |\n", .{ r.fixture, r.parser, r.throughput_mb_s, median_ms, r.iterations });
    }

    if (gate_rows.len != 0) {
        try w.writeAll("\n## Stable Gates\n\n");
        try w.writeAll("| Fixture | ours-turbo | libxml2 | yxml | pugixml | rapidxml | ours/strlen | Threshold | Result |\n");
        try w.writeAll("|---|---:|---:|---:|---:|---:|---:|---:|---|\n");
        for (gate_rows) |g| {
            try w.print(
                "| {s} | {d:.2} | {d:.2} | {d:.2} | {d:.2} | {d:.2} | {d:.3} | {d:.2} | {s} |\n",
                .{
                    g.fixture,
                    g.ours_turbo_mb_s,
                    g.libxml2_mb_s,
                    g.yxml_mb_s,
                    g.pugixml_mb_s,
                    g.rapidxml_mb_s,
                    g.strlen_ratio,
                    g.strlen_threshold,
                    if (g.pass) "PASS" else "FAIL",
                },
            );
        }
    }

    return out.toOwnedSlice(alloc);
}

fn writeTerminalReport(alloc: std.mem.Allocator, profile_name: []const u8, parse_results: []const ParseResult, gate_rows: []const GateRow) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(alloc);
    const w = out.writer(alloc);

    try w.print("FastXML Benchmark Results\nGenerated (unix): {d}\nProfile: {s}\n\n", .{ common.nowUnix(), profile_name });

    try w.writeAll("Parse Throughput (Per Fixture, sorted by speed)\n");

    var fixtures = std.ArrayList([]const u8).empty;
    defer fixtures.deinit(alloc);
    for (parse_results) |r| {
        var seen = false;
        for (fixtures.items) |name| {
            if (std.mem.eql(u8, name, r.fixture)) {
                seen = true;
                break;
            }
        }
        if (!seen) try fixtures.append(alloc, r.fixture);
    }

    const parse_headers = [_][]const u8{
        "Rank",
        "Parser",
        "Throughput (MB/s)",
        "Median Time (ms)",
        "Iterations",
    };
    const parse_header_align = [_]bool{ false, false, false, false, false };
    const parse_align = [_]bool{ true, false, true, true, true };

    for (fixtures.items) |fixture_name| {
        var fixture_rows = std.ArrayList(*const ParseResult).empty;
        defer fixture_rows.deinit(alloc);

        for (parse_results) |*r| {
            if (std.mem.eql(u8, r.fixture, fixture_name)) try fixture_rows.append(alloc, r);
        }
        if (fixture_rows.items.len == 0) continue;

        var i: usize = 1;
        while (i < fixture_rows.items.len) : (i += 1) {
            var j = i;
            while (j > 0 and fixture_rows.items[j - 1].*.throughput_mb_s < fixture_rows.items[j].*.throughput_mb_s) : (j -= 1) {
                std.mem.swap(*const ParseResult, &fixture_rows.items[j - 1], &fixture_rows.items[j]);
            }
        }

        const fastest = fixture_rows.items[0].*;
        try w.print(
            "\nFixture: {s} ({s})  Fastest: {s} @ {d:.2} MB/s\n",
            .{ fixture_name, if (fastest.is_real) "real" else "synthetic", fastest.parser, fastest.throughput_mb_s },
        );

        var parse_widths = [_]usize{
            parse_headers[0].len,
            parse_headers[1].len,
            parse_headers[2].len,
            parse_headers[3].len,
            parse_headers[4].len,
        };

        for (fixture_rows.items, 0..) |rp, idx| {
            var rank_buf: [16]u8 = undefined;
            const rank = try std.fmt.bufPrint(&rank_buf, "{d}", .{idx + 1});
            parse_widths[0] = maxUsize(parse_widths[0], rank.len);
            parse_widths[1] = maxUsize(parse_widths[1], rp.parser.len);

            var throughput_buf: [32]u8 = undefined;
            const throughput = try std.fmt.bufPrint(&throughput_buf, "{d:.2}", .{rp.throughput_mb_s});
            parse_widths[2] = maxUsize(parse_widths[2], throughput.len);

            var median_buf: [32]u8 = undefined;
            const median_ms = @as(f64, @floatFromInt(rp.median_ns)) / 1_000_000.0;
            const median = try std.fmt.bufPrint(&median_buf, "{d:.2}", .{median_ms});
            parse_widths[3] = maxUsize(parse_widths[3], median.len);

            var iter_buf: [32]u8 = undefined;
            const iterations = try std.fmt.bufPrint(&iter_buf, "{d}", .{rp.iterations});
            parse_widths[4] = maxUsize(parse_widths[4], iterations.len);
        }

        try writeTableBorder(w, &parse_widths);
        try writeTableRow(w, &parse_headers, &parse_widths, &parse_header_align);
        try writeTableBorder(w, &parse_widths);
        for (fixture_rows.items, 0..) |rp, idx| {
            var rank_buf: [16]u8 = undefined;
            const rank = try std.fmt.bufPrint(&rank_buf, "{d}", .{idx + 1});

            var throughput_buf: [32]u8 = undefined;
            const throughput = try std.fmt.bufPrint(&throughput_buf, "{d:.2}", .{rp.throughput_mb_s});

            var median_buf: [32]u8 = undefined;
            const median_ms = @as(f64, @floatFromInt(rp.median_ns)) / 1_000_000.0;
            const median = try std.fmt.bufPrint(&median_buf, "{d:.2}", .{median_ms});

            var iter_buf: [32]u8 = undefined;
            const iterations = try std.fmt.bufPrint(&iter_buf, "{d}", .{rp.iterations});

            const row = [_][]const u8{
                rank,
                rp.parser,
                throughput,
                median,
                iterations,
            };
            try writeTableRow(w, &row, &parse_widths, &parse_align);
        }
        try writeTableBorder(w, &parse_widths);
    }

    if (gate_rows.len != 0) {
        try w.writeAll("\nStable Gates\n");
        const gate_headers = [_][]const u8{
            "Fixture",
            "ours-turbo",
            "libxml2",
            "yxml",
            "pugixml",
            "rapidxml",
            "ours/strlen",
            "Threshold",
            "Result",
        };
        const gate_header_align = [_]bool{ false, false, false, false, false, false, false, false, false };
        const gate_align = [_]bool{ false, true, true, true, true, true, true, true, false };
        var gate_widths = [_]usize{
            gate_headers[0].len,
            gate_headers[1].len,
            gate_headers[2].len,
            gate_headers[3].len,
            gate_headers[4].len,
            gate_headers[5].len,
            gate_headers[6].len,
            gate_headers[7].len,
            gate_headers[8].len,
        };

        for (gate_rows) |g| {
            gate_widths[0] = maxUsize(gate_widths[0], g.fixture.len);

            var ours_buf: [32]u8 = undefined;
            const ours = try std.fmt.bufPrint(&ours_buf, "{d:.2}", .{g.ours_turbo_mb_s});
            gate_widths[1] = maxUsize(gate_widths[1], ours.len);

            var libxml2_buf: [32]u8 = undefined;
            const libxml2 = try std.fmt.bufPrint(&libxml2_buf, "{d:.2}", .{g.libxml2_mb_s});
            gate_widths[2] = maxUsize(gate_widths[2], libxml2.len);

            var yxml_buf: [32]u8 = undefined;
            const yxml = try std.fmt.bufPrint(&yxml_buf, "{d:.2}", .{g.yxml_mb_s});
            gate_widths[3] = maxUsize(gate_widths[3], yxml.len);

            var pugixml_buf: [32]u8 = undefined;
            const pugixml = try std.fmt.bufPrint(&pugixml_buf, "{d:.2}", .{g.pugixml_mb_s});
            gate_widths[4] = maxUsize(gate_widths[4], pugixml.len);

            var rapidxml_buf: [32]u8 = undefined;
            const rapidxml = try std.fmt.bufPrint(&rapidxml_buf, "{d:.2}", .{g.rapidxml_mb_s});
            gate_widths[5] = maxUsize(gate_widths[5], rapidxml.len);

            var ratio_buf: [32]u8 = undefined;
            const ratio = try std.fmt.bufPrint(&ratio_buf, "{d:.3}", .{g.strlen_ratio});
            gate_widths[6] = maxUsize(gate_widths[6], ratio.len);

            var threshold_buf: [32]u8 = undefined;
            const threshold = try std.fmt.bufPrint(&threshold_buf, "{d:.2}", .{g.strlen_threshold});
            gate_widths[7] = maxUsize(gate_widths[7], threshold.len);

            const result = if (g.pass) "PASS" else "FAIL";
            gate_widths[8] = maxUsize(gate_widths[8], result.len);
        }

        try writeTableBorder(w, &gate_widths);
        try writeTableRow(w, &gate_headers, &gate_widths, &gate_header_align);
        try writeTableBorder(w, &gate_widths);

        var pass_count: usize = 0;
        for (gate_rows) |g| {
            if (g.pass) pass_count += 1;

            var ours_buf: [32]u8 = undefined;
            const ours = try std.fmt.bufPrint(&ours_buf, "{d:.2}", .{g.ours_turbo_mb_s});

            var libxml2_buf: [32]u8 = undefined;
            const libxml2 = try std.fmt.bufPrint(&libxml2_buf, "{d:.2}", .{g.libxml2_mb_s});

            var yxml_buf: [32]u8 = undefined;
            const yxml = try std.fmt.bufPrint(&yxml_buf, "{d:.2}", .{g.yxml_mb_s});

            var pugixml_buf: [32]u8 = undefined;
            const pugixml = try std.fmt.bufPrint(&pugixml_buf, "{d:.2}", .{g.pugixml_mb_s});

            var rapidxml_buf: [32]u8 = undefined;
            const rapidxml = try std.fmt.bufPrint(&rapidxml_buf, "{d:.2}", .{g.rapidxml_mb_s});

            var ratio_buf: [32]u8 = undefined;
            const ratio = try std.fmt.bufPrint(&ratio_buf, "{d:.3}", .{g.strlen_ratio});

            var threshold_buf: [32]u8 = undefined;
            const threshold = try std.fmt.bufPrint(&threshold_buf, "{d:.2}", .{g.strlen_threshold});

            const row = [_][]const u8{
                g.fixture,
                ours,
                libxml2,
                yxml,
                pugixml,
                rapidxml,
                ratio,
                threshold,
                if (g.pass) "PASS" else "FAIL",
            };
            try writeTableRow(w, &row, &gate_widths, &gate_align);
        }
        try writeTableBorder(w, &gate_widths);
        try w.print("Gate Summary: {d}/{d} passed\n", .{ pass_count, gate_rows.len });
    }

    return out.toOwnedSlice(alloc);
}

fn writeJson(alloc: std.mem.Allocator, profile_name: []const u8, parse_results: []const ParseResult, gate_rows: []const GateRow) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(alloc);
    const w = out.writer(alloc);

    try w.print("{{\n  \"generated_unix\": {d},\n  \"profile\": \"{s}\",\n  \"parse_results\": [\n", .{ common.nowUnix(), profile_name });
    for (parse_results, 0..) |r, i| {
        try w.print(
            "    {{\"parser\":\"{s}\",\"fixture\":\"{s}\",\"is_real\":{s},\"iterations\":{d},\"median_ns\":{d},\"throughput_mb_s\":{d:.6}}}{s}\n",
            .{ r.parser, r.fixture, if (r.is_real) "true" else "false", r.iterations, r.median_ns, r.throughput_mb_s, if (i + 1 == parse_results.len) "" else "," },
        );
    }
    try w.writeAll("  ],\n  \"gates\": [\n");
    for (gate_rows, 0..) |g, i| {
        try w.print(
            "    {{\"fixture\":\"{s}\",\"is_real\":{s},\"ours_turbo_mb_s\":{d:.6},\"strlen_mb_s\":{d:.6},\"libxml2_mb_s\":{d:.6},\"yxml_mb_s\":{d:.6},\"pugixml_mb_s\":{d:.6},\"rapidxml_mb_s\":{d:.6},\"strlen_ratio\":{d:.6},\"strlen_threshold\":{d:.6},\"pass_sota\":{s},\"pass_strlen\":{s},\"pass\":{s}}}{s}\n",
            .{
                g.fixture,
                if (g.is_real) "true" else "false",
                g.ours_turbo_mb_s,
                g.strlen_mb_s,
                g.libxml2_mb_s,
                g.yxml_mb_s,
                g.pugixml_mb_s,
                g.rapidxml_mb_s,
                g.strlen_ratio,
                g.strlen_threshold,
                if (g.pass_sota) "true" else "false",
                if (g.pass_strlen) "true" else "false",
                if (g.pass) "true" else "false",
                if (i + 1 == gate_rows.len) "" else ",",
            },
        );
    }
    try w.writeAll("  ]\n}\n");

    return out.toOwnedSlice(alloc);
}

fn parseBaseline(alloc: std.mem.Allocator, bytes: []const u8) !std.StringHashMap(f64) {
    var map = std.StringHashMap(f64).init(alloc);
    errdefer {
        var it = map.iterator();
        while (it.next()) |kv| alloc.free(kv.key_ptr.*);
        map.deinit();
    }

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, bytes, .{});
    defer parsed.deinit();

    const root = parsed.value;
    const parse_results = root.object.get("parse_results") orelse return map;
    for (parse_results.array.items) |item| {
        const obj = item.object;
        const parser_name = obj.get("parser") orelse continue;
        const fixture_name = obj.get("fixture") orelse continue;
        const throughput = obj.get("throughput_mb_s") orelse continue;
        if (parser_name != .string or fixture_name != .string) continue;
        if (throughput != .float and throughput != .integer) continue;

        const key = try std.fmt.allocPrint(alloc, "{s}|{s}", .{ parser_name.string, fixture_name.string });
        const val: f64 = switch (throughput) {
            .float => throughput.float,
            .integer => @floatFromInt(throughput.integer),
            else => unreachable,
        };
        try map.put(key, val);
    }

    return map;
}

fn freeBaselineMap(alloc: std.mem.Allocator, map: *std.StringHashMap(f64)) void {
    var it = map.iterator();
    while (it.next()) |kv| {
        alloc.free(kv.key_ptr.*);
    }
    map.deinit();
}

fn runBenchmarks(alloc: std.mem.Allocator, args: []const []const u8) !void {
    var profile_name: []const u8 = "quick";
    var baseline_path: ?[]const u8 = null;
    var write_baseline = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--profile")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            profile_name = args[i];
        } else if (std.mem.eql(u8, arg, "--baseline")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            baseline_path = args[i];
        } else if (std.mem.eql(u8, arg, "--write-baseline")) {
            write_baseline = true;
        } else {
            return error.InvalidArguments;
        }
    }

    const profile = try getProfile(profile_name);

    try common.ensureDir(RESULTS_DIR);
    try setupParsers(alloc);
    try setupFixtures(alloc, false);
    try ensureExternalParsersBuilt(alloc);
    try buildRunners(alloc);

    var parse_results = std.ArrayList(ParseResult).empty;
    defer {
        for (parse_results.items) |*r| freeParseResult(alloc, r);
        parse_results.deinit(alloc);
    }

    for (profile.fixtures) |fx| {
        for (parse_parsers) |p| {
            std.debug.print("running parse: parser={s} fixture={s} iterations={d}\n", .{ p, fx.name, fx.iterations });
            try parse_results.append(alloc, try runParseBench(alloc, p, fx));
        }
    }

    const gate_rows = try evaluateGateRows(alloc, profile, parse_results.items);
    defer freeGateRows(alloc, gate_rows);

    const md = try writeMarkdown(alloc, profile.name, parse_results.items, gate_rows);
    defer alloc.free(md);
    try common.writeFile(RESULTS_DIR ++ "/latest.md", md);

    const terminal = try writeTerminalReport(alloc, profile.name, parse_results.items, gate_rows);
    defer alloc.free(terminal);

    const json = try writeJson(alloc, profile.name, parse_results.items, gate_rows);
    defer alloc.free(json);
    try common.writeFile(RESULTS_DIR ++ "/latest.json", json);

    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll("\n");
    try stdout.writeAll(terminal);
    try stdout.writeAll("\n");
    try stdout.flush();

    const baseline_default = try std.fmt.allocPrint(alloc, RESULTS_DIR ++ "/baseline_{s}.json", .{profile.name});
    defer alloc.free(baseline_default);
    const baseline = baseline_path orelse baseline_default;

    if (write_baseline) {
        try common.writeFile(baseline, json);
        std.debug.print("wrote baseline {s}\n", .{baseline});
    }

    var failed = false;

    if (std.mem.eql(u8, profile.name, "stable")) {
        for (gate_rows) |g| {
            if (!g.pass) {
                failed = true;
                std.debug.print(
                    "gate fail: {s} ours={d:.2} libxml2={d:.2} yxml={d:.2} pugixml={d:.2} rapidxml={d:.2} ratio={d:.3} threshold={d:.2}\n",
                    .{ g.fixture, g.ours_turbo_mb_s, g.libxml2_mb_s, g.yxml_mb_s, g.pugixml_mb_s, g.rapidxml_mb_s, g.strlen_ratio, g.strlen_threshold },
                );
            }
        }
    }

    if (pathExists(baseline)) {
        const baseline_bytes = try common.readFileAlloc(alloc, baseline);
        defer alloc.free(baseline_bytes);

        var base_map = try parseBaseline(alloc, baseline_bytes);
        defer freeBaselineMap(alloc, &base_map);

        for (parse_results.items) |r| {
            if (!std.mem.startsWith(u8, r.parser, "ours-")) continue;
            const key = try std.fmt.allocPrint(alloc, "{s}|{s}", .{ r.parser, r.fixture });
            defer alloc.free(key);
            const base = base_map.get(key) orelse continue;
            if (r.throughput_mb_s < base * 0.97) {
                failed = true;
                std.debug.print(
                    "baseline drift: {s} {s} current={d:.2} baseline={d:.2}\n",
                    .{ r.parser, r.fixture, r.throughput_mb_s, base },
                );
            }
        }
    }

    std.debug.print("wrote {s}/latest.md and {s}/latest.json\n", .{ RESULTS_DIR, RESULTS_DIR });

    if (failed) return error.BenchmarkGateFailed;
}

fn usage() void {
    std.debug.print(
        \\usage:
        \\  fastxml-tools setup-parsers
        \\  fastxml-tools setup-fixtures [--refresh]
        \\  fastxml-tools run-benchmarks [--profile quick|stable] [--baseline path] [--write-baseline]
        \\  fastxml-tools run-conformance [--suite path]...
        \\  fastxml-tools run-compliance [--suite path]...   (alias)
        \\
    , .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);

    if (args.len < 2) {
        usage();
        std.process.exit(2);
    }

    const cmd = args[1];
    if (std.mem.eql(u8, cmd, "setup-parsers")) {
        try setupParsers(alloc);
        return;
    }

    if (std.mem.eql(u8, cmd, "setup-fixtures")) {
        var refresh = false;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--refresh")) refresh = true else return error.InvalidArguments;
        }
        try setupFixtures(alloc, refresh);
        return;
    }

    if (std.mem.eql(u8, cmd, "run-benchmarks")) {
        try runBenchmarks(alloc, args[2..]);
        return;
    }

    if (std.mem.eql(u8, cmd, "run-conformance") or std.mem.eql(u8, cmd, "run-compliance")) {
        try conformance.runConformance(alloc, args[2..]);
        return;
    }

    usage();
    std.process.exit(2);
}
