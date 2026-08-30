const std = @import("std");
const common = @import("common.zig");
const conformance = @import("conformance.zig");

const REPO_ROOT = ".";
const BUILD_DIR = "bench/build";
const BIN_DIR = "bench/build/bin";
const TMP_SCRATCH_DIR = BUILD_DIR ++ "/tmp";
const RESULTS_DIR = "bench/results";
const FIXTURES_DIR = "bench/fixtures";
const PARSERS_DIR = "bench/parsers";
const min_sample_ns: u64 = 20_000_000;
const ReadmeSummaryStartMarker = "<!-- README_AUTO_SUMMARY:START -->";
const ReadmeSummaryEndMarker = "<!-- README_AUTO_SUMMARY:END -->";
const BenchReadmeSnapshotStartMarker = "<!-- BENCH_README_AUTO_SNAPSHOT:START -->";
const BenchReadmeSnapshotEndMarker = "<!-- BENCH_README_AUTO_SNAPSHOT:END -->";
const max_opaque_cdata_ratio = 0.90;

const repeats: usize = 5;

const parse_parsers = [_][]const u8{
    "ours-strict",
    "ours-turbo",
    "stream-strict",
    "stream-turbo",
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
    .{ .name = "hnrss.xml", .iterations = 80, .is_real = true },
    .{ .name = "xkcd_rss.xml", .iterations = 100, .is_real = true },
    .{ .name = "bbc_world.xml", .iterations = 80, .is_real = true },
    .{ .name = "arxiv_cs.xml", .iterations = 80, .is_real = true },
    .{ .name = "ecb_usd.xml", .iterations = 120, .is_real = true },
    .{ .name = "pugixml_large.xml", .iterations = 24, .is_real = true },
    .{ .name = "weekly_utf8.xml", .iterations = 100, .is_real = true },
    .{ .name = "xgconsole.xml", .iterations = 160, .is_real = true },
    .{ .name = "synthetic_flat_attrs.xml", .iterations = 120, .is_real = false },
    .{ .name = "synthetic_deep_tree.xml", .iterations = 150, .is_real = false },
    .{ .name = "synthetic_entities.xml", .iterations = 100, .is_real = false },
    .{ .name = "synthetic_cdata_mix.xml", .iterations = 100, .is_real = false },
    .{ .name = "synthetic_wide_siblings.xml", .iterations = 120, .is_real = false },
    .{ .name = "synthetic_namespace_mix.xml", .iterations = 120, .is_real = false },
    .{ .name = "synthetic_long_names.xml", .iterations = 120, .is_real = false },
    .{ .name = "synthetic_self_closing_swarm.xml", .iterations = 120, .is_real = false },
};

const stable_fixtures = [_]FixtureCase{
    .{ .name = "note.xml", .iterations = 300, .is_real = true },
    .{ .name = "sitemaps.xml", .iterations = 300, .is_real = true },
    .{ .name = "plant_catalog.xml", .iterations = 140, .is_real = true },
    .{ .name = "cd_catalog.xml", .iterations = 200, .is_real = true },
    .{ .name = "hnrss.xml", .iterations = 200, .is_real = true },
    .{ .name = "xkcd_rss.xml", .iterations = 220, .is_real = true },
    .{ .name = "bbc_world.xml", .iterations = 180, .is_real = true },
    .{ .name = "arxiv_cs.xml", .iterations = 180, .is_real = true },
    .{ .name = "ecb_usd.xml", .iterations = 220, .is_real = true },
    .{ .name = "tree.xml", .iterations = 240, .is_real = true },
    .{ .name = "character.xml", .iterations = 260, .is_real = true },
    .{ .name = "transitions.xml", .iterations = 260, .is_real = true },
    .{ .name = "xgconsole.xml", .iterations = 320, .is_real = true },
    .{ .name = "weekly_utf8.xml", .iterations = 220, .is_real = true },
    .{ .name = "pugixml_large.xml", .iterations = 40, .is_real = true },
    .{ .name = "synthetic_flat_attrs.xml", .iterations = 280, .is_real = false },
    .{ .name = "synthetic_deep_tree.xml", .iterations = 320, .is_real = false },
    .{ .name = "synthetic_entities.xml", .iterations = 240, .is_real = false },
    .{ .name = "synthetic_cdata_mix.xml", .iterations = 240, .is_real = false },
    .{ .name = "synthetic_wide_siblings.xml", .iterations = 260, .is_real = false },
    .{ .name = "synthetic_namespace_mix.xml", .iterations = 220, .is_real = false },
    .{ .name = "synthetic_long_names.xml", .iterations = 220, .is_real = false },
    .{ .name = "synthetic_self_closing_swarm.xml", .iterations = 220, .is_real = false },
    .{ .name = "synthetic_mixed_content.xml", .iterations = 220, .is_real = false },
    .{ .name = "synthetic_small_records.xml", .iterations = 200, .is_real = false },
};

const ParseResult = struct {
    parser: []const u8,
    fixture: []const u8,
    is_real: bool,
    iterations: usize,
    /// Raw timing samples kept so JSON/markdown reports can expose run-to-run
    /// spread without rerunning the benchmark.
    samples_ns: []u64,
    median_ns: u64,
    throughput_mb_s: f64,
};

const GateRow = struct {
    fixture: []const u8,
    is_real: bool,
    ours_turbo_mb_s: f64,
    pugixml_mb_s: f64,
    rapidxml_mb_s: f64,
    best_external_parser: []const u8,
    best_external_mb_s: f64,
    /// Ratio against the faster external DOM parser for this fixture.
    external_ratio: f64,
    pass: bool,
};

const StreamGateRow = struct {
    fixture: []const u8,
    is_real: bool,
    dom_turbo_mb_s: f64,
    stream_turbo_mb_s: f64,
    turbo_ratio: f64,
    dom_strict_mb_s: f64,
    stream_strict_mb_s: f64,
    strict_ratio: f64,
    pass: bool,
};

fn getProfile(name: []const u8) !Profile {
    if (std.mem.eql(u8, name, "quick")) return .{ .name = "quick", .fixtures = &quick_fixtures };
    if (std.mem.eql(u8, name, "stable")) return .{ .name = "stable", .fixtures = &stable_fixtures };
    return error.InvalidProfile;
}

const pugixml_required_files = [_][]const u8{
    "CMakeLists.txt",
    "src/pugixml.cpp",
    "src/pugixml.hpp",
    "docs/samples/tree.xml",
    "docs/samples/character.xml",
    "docs/samples/transitions.xml",
    "docs/samples/xgconsole.xml",
    "docs/samples/weekly-utf-8.xml",
    "tests/data/large.xml",
};

const rapidxml_files = [_][]const u8{
    "rapidxml.hpp",
    "rapidxml_iterators.hpp",
    "rapidxml_print.hpp",
    "rapidxml_utils.hpp",
    "license.txt",
};

fn allFilesExistUnder(io: std.Io, alloc: std.mem.Allocator, base: []const u8, files: []const []const u8) !bool {
    for (files) |file| {
        const path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ base, file });
        defer alloc.free(path);
        if (!common.fileExists(io, path)) return false;
    }
    return true;
}

fn setupParsers(io: std.Io, alloc: std.mem.Allocator) !void {
    try common.ensureDir(io, PARSERS_DIR);
    try common.ensureDir(io, BUILD_DIR);

    const pugixml_dir = PARSERS_DIR ++ "/pugixml";
    const pugixml_git = pugixml_dir ++ "/.git";
    if (!common.fileExists(io, pugixml_git)) {
        // A failed/interrupted clone can leave the destination directory behind
        // without a usable repository. Since bench/parsers is generated state,
        // remove that stale target before retrying the clone.
        if (common.fileExists(io, pugixml_dir)) {
            try std.Io.Dir.cwd().deleteTree(io, pugixml_dir);
        }
        const argv = [_][]const u8{ "git", "clone", "--depth", "1", "https://github.com/zeux/pugixml.git", pugixml_dir };
        try common.runInherit(io, alloc, &argv, REPO_ROOT);
        if (!try allFilesExistUnder(io, alloc, pugixml_dir, &pugixml_required_files)) {
            return error.IncompleteExternalParser;
        }
    } else if (!try allFilesExistUnder(io, alloc, pugixml_dir, &pugixml_required_files)) {
        // bench/parsers is generated/ignored state. Repair deleted or partially
        // populated tracked files instead of treating the mere presence of
        // `.git` as a complete checkout.
        const repair = [_][]const u8{ "git", "-C", pugixml_dir, "reset", "--hard", "HEAD" };
        try common.runInherit(io, alloc, &repair, REPO_ROOT);
        if (!try allFilesExistUnder(io, alloc, pugixml_dir, &pugixml_required_files)) {
            return error.IncompleteExternalParser;
        }
    } else {
        std.debug.print("already present: pugixml\n", .{});
    }

    const rapid_dst = PARSERS_DIR ++ "/rapidxml";
    const rapid_local_src = "rapidxml-1.13";
    const rapid_cached_src = BUILD_DIR ++ "/rapidxml-src/rapidxml-1.13";
    try common.ensureDir(io, rapid_dst);

    if (!try allFilesExistUnder(io, alloc, rapid_dst, &rapidxml_files)) {
        var source_root: []const u8 = undefined;
        if (try allFilesExistUnder(io, alloc, rapid_local_src, &rapidxml_files)) {
            source_root = rapid_local_src;
        } else if (try allFilesExistUnder(io, alloc, rapid_cached_src, &rapidxml_files)) {
            source_root = rapid_cached_src;
        } else {
            const zip_path = BUILD_DIR ++ "/rapidxml-1.13.zip";
            const rapid_tmp = BUILD_DIR ++ "/rapidxml-src";
            try common.ensureDir(io, rapid_tmp);
            const curl = [_][]const u8{
                "curl",
                "-L",
                "--fail",
                "https://downloads.sourceforge.net/project/rapidxml/rapidxml/rapidxml%201.13/rapidxml-1.13.zip",
                "-o",
                zip_path,
            };
            try common.runInherit(io, alloc, &curl, REPO_ROOT);
            const unzip = [_][]const u8{ "unzip", "-oq", zip_path, "-d", rapid_tmp };
            try common.runInherit(io, alloc, &unzip, REPO_ROOT);
            if (!try allFilesExistUnder(io, alloc, rapid_cached_src, &rapidxml_files)) {
                return error.IncompleteExternalParser;
            }
            source_root = rapid_cached_src;
        }

        for (rapidxml_files) |file| {
            const dst = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ rapid_dst, file });
            defer alloc.free(dst);
            if (common.fileExists(io, dst)) continue;
            const src = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ source_root, file });
            defer alloc.free(src);
            const cp = [_][]const u8{ "cp", src, dst };
            try common.runInherit(io, alloc, &cp, REPO_ROOT);
        }
    }

    if (!try allFilesExistUnder(io, alloc, rapid_dst, &rapidxml_files)) return error.IncompleteExternalParser;
    std.debug.print("parsers ready\n", .{});
}

fn writeSyntheticFixtures(io: std.Io) !void {
    try writeFlatAttrs(io, FIXTURES_DIR ++ "/synthetic_flat_attrs.xml");
    try writeDeepTree(io, FIXTURES_DIR ++ "/synthetic_deep_tree.xml");
    try writeEntities(io, FIXTURES_DIR ++ "/synthetic_entities.xml");
    try writeCdataMix(io, FIXTURES_DIR ++ "/synthetic_cdata_mix.xml");
    try writeWideSiblings(io, FIXTURES_DIR ++ "/synthetic_wide_siblings.xml");
    try writeNamespaceMix(io, FIXTURES_DIR ++ "/synthetic_namespace_mix.xml");
    try writeLongNames(io, FIXTURES_DIR ++ "/synthetic_long_names.xml");
    try writeSelfClosingSwarm(io, FIXTURES_DIR ++ "/synthetic_self_closing_swarm.xml");
    try writeMixedContent(io, FIXTURES_DIR ++ "/synthetic_mixed_content.xml");
    try writeSmallRecords(io, FIXTURES_DIR ++ "/synthetic_small_records.xml");
}

fn writeFlatAttrs(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<rows>");
    var i: usize = 0;
    while (i < 3000) : (i += 1) {
        try out.print("<row id='{d}' a='x' b='y' c='z' d='w' e='q' f='n' g='m' h='k' i='j' j='t'/>", .{i});
    }
    try out.writeAll("</rows>");
    try out.flush();
}

fn writeDeepTree(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
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

fn writeEntities(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<root>");
    var i: usize = 0;
    while (i < 9000) : (i += 1) {
        try out.writeAll("<item v='&amp;&lt;&gt;&quot;&apos;'>&#65;&#x42;&amp;ok&lt;test&gt;</item>");
    }
    try out.writeAll("</root>");
    try out.flush();
}

fn writeCdataMix(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<?xml version='1.0'?><!DOCTYPE doc [<!ELEMENT doc ANY>]><doc>");
    var i: usize = 0;
    while (i < 2000) : (i += 1) {
        try out.print("<!--c{d}--><![CDATA[data<{d}>]]><?pi value='{d}'?><x>{d}</x>", .{ i, i, i, i });
    }
    try out.writeAll("</doc>");
    try out.flush();
}

fn writeWideSiblings(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<root>");
    var i: usize = 0;
    while (i < 16000) : (i += 1) {
        try out.print("<n id='{d}'>v{d}</n>", .{ i, i });
    }
    try out.writeAll("</root>");
    try out.flush();
}

fn writeNamespaceMix(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll(
        "<feed xmlns='urn:root' xmlns:a='urn:a' xmlns:b='urn:b' xmlns:c='urn:c'>",
    );
    var i: usize = 0;
    while (i < 5000) : (i += 1) {
        try out.print(
            "<a:item id='{d}' a:key='alpha' b:key='beta' c:key='gamma'><b:title>entry-{d}</b:title><c:meta code='x{d}'/></a:item>",
            .{ i, i, i },
        );
    }
    try out.writeAll("</feed>");
    try out.flush();
}

fn writeLongNames(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<root>");
    var i: usize = 0;
    while (i < 3500) : (i += 1) {
        try out.print(
            "<customer_order_transaction_record_{d} long_attribute_identifier_primary='value-{d}' long_attribute_identifier_secondary='payload-{d}'><customer_order_transaction_payload_{d}>text-{d}</customer_order_transaction_payload_{d}></customer_order_transaction_record_{d}>",
            .{ i, i, i, i, i, i, i },
        );
    }
    try out.writeAll("</root>");
    try out.flush();
}

fn writeSelfClosingSwarm(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<root>");
    var i: usize = 0;
    while (i < 32000) : (i += 1) {
        try out.print("<entry id='{d}' kind='sample' state='ok'/>", .{i});
    }
    try out.writeAll("</root>");
    try out.flush();
}

fn writeMixedContent(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<?xml version='1.0'?><doc>");
    var i: usize = 0;
    while (i < 6000) : (i += 1) {
        try out.print(
            "<p>prefix-{d}<b>bold-{d}</b><![CDATA[cdata-{d}<x>]]><!--m{d}--><?go value='{d}'?><i>tail-{d}</i></p>",
            .{ i, i, i, i, i, i },
        );
    }
    try out.writeAll("</doc>");
    try out.flush();
}

fn writeSmallRecords(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<records>");
    var i: usize = 0;
    while (i < 12000) : (i += 1) {
        try out.print(
            "<record id='{d}'><name>name-{d}</name><kind>k</kind><value>{d}</value><flag>true</flag></record>",
            .{ i, i, i },
        );
    }
    try out.writeAll("</records>");
    try out.flush();
}

fn copyFixtureIfPresent(io: std.Io, alloc: std.mem.Allocator, src: []const u8, dst_name: []const u8, refresh: bool) !void {
    const dst = try std.fmt.allocPrint(alloc, FIXTURES_DIR ++ "/{s}", .{dst_name});
    defer alloc.free(dst);

    if (!refresh) {
        const st = std.Io.Dir.cwd().statFile(io, dst, .{}) catch null;
        if (st != null and st.?.size > 0) {
            std.debug.print("cached: {s}\n", .{dst_name});
            return;
        }
    }

    const src_stat = std.Io.Dir.cwd().statFile(io, src, .{}) catch null;
    if (src_stat == null or src_stat.?.size == 0) return;

    const bytes = try common.readFileAlloc(io, alloc, src);
    defer alloc.free(bytes);
    try common.writeFile(io, dst, bytes);
}

fn ensureFixtureIsNotOpaqueCdata(io: std.Io, alloc: std.mem.Allocator, path: []const u8, fixture_name: []const u8) !void {
    // Extremely CDATA-heavy fixtures mostly benchmark raw byte copying rather
    // than DOM work, so reject them before they skew parser comparisons.
    const bytes = try common.readFileAlloc(io, alloc, path);
    defer alloc.free(bytes);
    if (bytes.len == 0) return error.InvalidFixture;

    var cdata_bytes: usize = 0;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, i, "<![CDATA[")) |start| {
        const content_start = start + "<![CDATA[".len;
        const end = std.mem.indexOfPos(u8, bytes, content_start, "]]>") orelse break;
        cdata_bytes += end - content_start;
        i = end + "]]>".len;
    }

    const ratio = @as(f64, @floatFromInt(cdata_bytes)) / @as(f64, @floatFromInt(bytes.len));
    if (ratio > max_opaque_cdata_ratio) {
        std.debug.print(
            "fixture rejected: {s} is {d:.3}% CDATA payload and would skew DOM benchmarks\n",
            .{ fixture_name, ratio * 100.0 },
        );
        return error.InvalidFixture;
    }
}

fn setupFixtures(io: std.Io, alloc: std.mem.Allocator, refresh: bool) !void {
    try common.ensureDir(io, FIXTURES_DIR);

    const targets = [_]struct { url: []const u8, out: []const u8 }{
        .{ .url = "https://www.w3schools.com/xml/note.xml", .out = "note.xml" },
        .{ .url = "https://www.sitemaps.org/sitemap.xml", .out = "sitemaps.xml" },
        .{ .url = "https://www.w3schools.com/xml/plant_catalog.xml", .out = "plant_catalog.xml" },
        .{ .url = "https://www.w3schools.com/xml/cd_catalog.xml", .out = "cd_catalog.xml" },
        .{ .url = "https://hnrss.org/frontpage", .out = "hnrss.xml" },
        .{ .url = "https://xkcd.com/rss.xml", .out = "xkcd_rss.xml" },
        .{ .url = "https://feeds.bbci.co.uk/news/world/rss.xml", .out = "bbc_world.xml" },
        .{ .url = "https://export.arxiv.org/rss/cs", .out = "arxiv_cs.xml" },
        .{ .url = "https://www.ecb.europa.eu/rss/fxref-usd.html", .out = "ecb_usd.xml" },
    };

    for (targets) |item| {
        const target = try std.fmt.allocPrint(alloc, FIXTURES_DIR ++ "/{s}", .{item.out});
        defer alloc.free(target);

        if (!refresh) {
            const st = std.Io.Dir.cwd().statFile(io, target, .{}) catch null;
            if (st != null and st.?.size > 0) {
                ensureFixtureIsNotOpaqueCdata(io, alloc, target, item.out) catch |err| switch (err) {
                    error.InvalidFixture => std.Io.Dir.cwd().deleteFile(io, target) catch {},
                    else => return err,
                };
                if (common.fileExists(io, target)) {
                    std.debug.print("cached: {s}\n", .{item.out});
                    continue;
                }
            }
        }

        const download_target = try std.fmt.allocPrint(alloc, "{s}.download", .{target});
        defer alloc.free(download_target);
        std.Io.Dir.cwd().deleteFile(io, download_target) catch {};
        errdefer std.Io.Dir.cwd().deleteFile(io, download_target) catch {};

        const argv = [_][]const u8{
            "curl",
            "-L",
            "--fail",
            "--retry",
            "2",
            "--retry-delay",
            "1",
            "-A",
            "zxml-bench/1.0",
            item.url,
            "-o",
            download_target,
        };
        try common.runInherit(io, alloc, &argv, REPO_ROOT);
        try ensureFixtureIsNotOpaqueCdata(io, alloc, download_target, item.out);
        const cwd = std.Io.Dir.cwd();
        try cwd.rename(download_target, cwd, target, io);
    }

    const bundled = [_]struct { src: []const u8, out: []const u8 }{
        .{ .src = PARSERS_DIR ++ "/pugixml/docs/samples/tree.xml", .out = "tree.xml" },
        .{ .src = PARSERS_DIR ++ "/pugixml/docs/samples/character.xml", .out = "character.xml" },
        .{ .src = PARSERS_DIR ++ "/pugixml/docs/samples/transitions.xml", .out = "transitions.xml" },
        .{ .src = PARSERS_DIR ++ "/pugixml/docs/samples/xgconsole.xml", .out = "xgconsole.xml" },
        .{ .src = PARSERS_DIR ++ "/pugixml/docs/samples/weekly-utf-8.xml", .out = "weekly_utf8.xml" },
        .{ .src = PARSERS_DIR ++ "/pugixml/tests/data/large.xml", .out = "pugixml_large.xml" },
    };
    for (bundled) |item| {
        try copyFixtureIfPresent(io, alloc, item.src, item.out, refresh);
    }

    try writeSyntheticFixtures(io);
    std.debug.print("fixtures ready\n", .{});
}

fn ensureExternalParsersBuilt(io: std.Io, alloc: std.mem.Allocator) !void {
    if (!common.fileExists(io, PARSERS_DIR ++ "/pugixml/CMakeLists.txt")) {
        try setupParsers(io, alloc);
    }
}

fn runInheritWithBenchTmp(io: std.Io, alloc: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) !void {
    // Force toolchain temp files under the repo-local scratch dir so large C++
    // benchmark builds do not fail on small system `/tmp` quotas.
    var with_env = std.ArrayList([]const u8).empty;
    defer with_env.deinit(alloc);
    try with_env.appendSlice(alloc, &.{
        "env",
        "TMPDIR=" ++ TMP_SCRATCH_DIR,
        "TMP=" ++ TMP_SCRATCH_DIR,
        "TEMP=" ++ TMP_SCRATCH_DIR,
    });
    try with_env.appendSlice(alloc, argv);
    try common.runInherit(io, alloc, with_env.items, cwd);
}

fn buildRunners(io: std.Io, alloc: std.mem.Allocator) !void {
    try common.ensureDir(io, BUILD_DIR);
    try common.ensureDir(io, BIN_DIR);
    try common.ensureDir(io, TMP_SCRATCH_DIR);

    const zig_build = [_][]const u8{ "zig", "build", "-Doptimize=ReleaseFast", "-Dcpu=native" };
    try runInheritWithBenchTmp(io, alloc, &zig_build, REPO_ROOT);

    const copy_ours = [_][]const u8{
        "cp",
        "zig-out/bin/ours_runner",
        "bench/build/bin/ours_runner",
    };
    try runInheritWithBenchTmp(io, alloc, &copy_ours, REPO_ROOT);

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
    try runInheritWithBenchTmp(io, alloc, &pugixml_cc, REPO_ROOT);

    const rapidxml_cc = [_][]const u8{
        "c++",
        "-O3",
        "-std=c++17",
        "bench/runners/rapidxml_runner.cpp",
        "-Ibench/parsers/rapidxml",
        "-o",
        "bench/build/bin/rapidxml_runner",
    };
    try runInheritWithBenchTmp(io, alloc, &rapidxml_cc, REPO_ROOT);
}

fn runParser(io: std.Io, alloc: std.mem.Allocator, parser_name: []const u8, fixture_path: []const u8, iterations: usize) !u64 {
    const iters = try std.fmt.allocPrint(alloc, "{d}", .{iterations});
    defer alloc.free(iters);

    // Do not require Linux-specific CPU affinity tooling here. Benchmarking
    // should still work in minimal containers and restricted cpusets where
    // `taskset` is absent or CPU 0 is unavailable.
    var argv: [4][]const u8 = undefined;
    var argc: usize = 0;

    if (std.mem.eql(u8, parser_name, "ours-strict")) {
        argv[argc + 0] = BIN_DIR ++ "/ours_runner";
        argv[argc + 1] = "strict";
        argv[argc + 2] = fixture_path;
        argv[argc + 3] = iters;
        argc += 4;
    } else if (std.mem.eql(u8, parser_name, "ours-turbo")) {
        argv[argc + 0] = BIN_DIR ++ "/ours_runner";
        argv[argc + 1] = "turbo";
        argv[argc + 2] = fixture_path;
        argv[argc + 3] = iters;
        argc += 4;
    } else if (std.mem.eql(u8, parser_name, "stream-strict")) {
        argv[argc + 0] = BIN_DIR ++ "/ours_runner";
        argv[argc + 1] = "stream-strict";
        argv[argc + 2] = fixture_path;
        argv[argc + 3] = iters;
        argc += 4;
    } else if (std.mem.eql(u8, parser_name, "stream-turbo")) {
        argv[argc + 0] = BIN_DIR ++ "/ours_runner";
        argv[argc + 1] = "stream-turbo";
        argv[argc + 2] = fixture_path;
        argv[argc + 3] = iters;
        argc += 4;
    } else if (std.mem.eql(u8, parser_name, "pugixml")) {
        argv[argc + 0] = BIN_DIR ++ "/pugixml_runner";
        argv[argc + 1] = fixture_path;
        argv[argc + 2] = iters;
        argc += 3;
    } else if (std.mem.eql(u8, parser_name, "rapidxml")) {
        argv[argc + 0] = BIN_DIR ++ "/rapidxml_runner";
        argv[argc + 1] = fixture_path;
        argv[argc + 2] = iters;
        argc += 3;
    } else {
        return error.UnknownParser;
    }

    const out = try common.runCaptureStdout(io, alloc, argv[0..argc], REPO_ROOT);
    defer alloc.free(out);
    return common.parseExactU64(out);
}

fn runParseBench(io: std.Io, alloc: std.mem.Allocator, parser_name: []const u8, fixture: FixtureCase) !ParseResult {
    const fixture_path = try std.fmt.allocPrint(alloc, FIXTURES_DIR ++ "/{s}", .{fixture.name});
    defer alloc.free(fixture_path);

    const fixture_stat = try std.Io.Dir.cwd().statFile(io, fixture_path, .{});

    const calibrated_iterations = try calibrateIterations(io, alloc, parser_name, fixture_path, fixture.iterations);

    const samples = try alloc.alloc(u64, repeats);
    errdefer alloc.free(samples);
    for (samples, 0..) |*s, rep| {
        _ = rep;
        s.* = try runParser(io, alloc, parser_name, fixture_path, calibrated_iterations);
    }

    const median = try common.medianU64(alloc, samples);
    const bytes_total = @as(f64, @floatFromInt(fixture_stat.size)) * @as(f64, @floatFromInt(calibrated_iterations));
    const throughput = if (median == 0) 0.0 else (bytes_total / (1024.0 * 1024.0)) / (@as(f64, @floatFromInt(median)) / 1_000_000_000.0);

    const parser_name_copy = try alloc.dupe(u8, parser_name);
    errdefer alloc.free(parser_name_copy);
    const fixture_name_copy = try alloc.dupe(u8, fixture.name);
    errdefer alloc.free(fixture_name_copy);

    return .{
        .parser = parser_name_copy,
        .fixture = fixture_name_copy,
        .is_real = fixture.is_real,
        .iterations = calibrated_iterations,
        .samples_ns = samples,
        .median_ns = median,
        .throughput_mb_s = throughput,
    };
}

fn calibrateIterations(io: std.Io, alloc: std.mem.Allocator, parser_name: []const u8, fixture_path: []const u8, base_iterations: usize) !usize {
    // Keep each sample above a minimum wall-clock duration so median timings are
    // not dominated by timer granularity on tiny fixtures.
    const base_ns = try runParser(io, alloc, parser_name, fixture_path, base_iterations);
    if (base_ns >= min_sample_ns or base_ns == 0) return base_iterations;

    const factor_u64 = std.math.divCeil(u64, min_sample_ns, base_ns) catch return base_iterations;
    const factor = @as(usize, @intCast(@min(factor_u64, 10_000)));
    return try std.math.mul(usize, base_iterations, factor);
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
    errdefer {
        for (out.items) |r| alloc.free(r.fixture);
        out.deinit(alloc);
    }

    for (profile.fixtures) |fx| {
        const ours = findThroughput(rows, "ours-turbo", fx.name) orelse return error.MissingBenchmarkResult;
        const pugixml = findThroughput(rows, "pugixml", fx.name) orelse return error.MissingBenchmarkResult;
        const rapidxml = findThroughput(rows, "rapidxml", fx.name) orelse return error.MissingBenchmarkResult;

        const best_external_mb_s: f64 = if (pugixml >= rapidxml) pugixml else rapidxml;
        const best_external_parser = if (pugixml >= rapidxml) "pugixml" else "rapidxml";
        const ratio = if (best_external_mb_s == 0) 0 else ours / best_external_mb_s;

        const fixture = try alloc.dupe(u8, fx.name);
        errdefer alloc.free(fixture);
        try out.append(alloc, .{
            .fixture = fixture,
            .is_real = fx.is_real,
            .ours_turbo_mb_s = ours,
            .pugixml_mb_s = pugixml,
            .rapidxml_mb_s = rapidxml,
            .best_external_parser = best_external_parser,
            .best_external_mb_s = best_external_mb_s,
            .external_ratio = ratio,
            .pass = ratio >= 1.0,
        });
    }

    return out.toOwnedSlice(alloc);
}

fn freeGateRows(alloc: std.mem.Allocator, rows: []GateRow) void {
    for (rows) |r| alloc.free(r.fixture);
    alloc.free(rows);
}

fn evaluateStreamGateRows(alloc: std.mem.Allocator, profile: Profile, rows: []const ParseResult) ![]StreamGateRow {
    var out = std.ArrayList(StreamGateRow).empty;
    errdefer {
        for (out.items) |r| alloc.free(r.fixture);
        out.deinit(alloc);
    }

    for (profile.fixtures) |fx| {
        const dom_turbo = findThroughput(rows, "ours-turbo", fx.name) orelse return error.MissingBenchmarkResult;
        const stream_turbo = findThroughput(rows, "stream-turbo", fx.name) orelse return error.MissingBenchmarkResult;
        const dom_strict = findThroughput(rows, "ours-strict", fx.name) orelse return error.MissingBenchmarkResult;
        const stream_strict = findThroughput(rows, "stream-strict", fx.name) orelse return error.MissingBenchmarkResult;

        const turbo_ratio = if (dom_turbo == 0) 0 else stream_turbo / dom_turbo;
        const strict_ratio = if (dom_strict == 0) 0 else stream_strict / dom_strict;
        const fixture = try alloc.dupe(u8, fx.name);
        errdefer alloc.free(fixture);
        try out.append(alloc, .{
            .fixture = fixture,
            .is_real = fx.is_real,
            .dom_turbo_mb_s = dom_turbo,
            .stream_turbo_mb_s = stream_turbo,
            .turbo_ratio = turbo_ratio,
            .dom_strict_mb_s = dom_strict,
            .stream_strict_mb_s = stream_strict,
            .strict_ratio = strict_ratio,
            .pass = turbo_ratio >= 1.0 and strict_ratio >= 1.0,
        });
    }

    return out.toOwnedSlice(alloc);
}

fn freeStreamGateRows(alloc: std.mem.Allocator, rows: []StreamGateRow) void {
    for (rows) |r| alloc.free(r.fixture);
    alloc.free(rows);
}

const AverageThroughputRow = struct {
    parser: []const u8,
    avg_mb_s: f64,
};

fn makeAverageThroughputRows(alloc: std.mem.Allocator, parse_results: []const ParseResult) ![]AverageThroughputRow {
    const parser_names = [_][]const u8{ "ours-turbo", "ours-strict", "stream-turbo", "stream-strict", "pugixml", "rapidxml" };
    var out = try alloc.alloc(AverageThroughputRow, parser_names.len);
    errdefer alloc.free(out);

    for (parser_names, 0..) |parser_name, idx| {
        var sum: f64 = 0.0;
        var count: usize = 0;
        for (parse_results) |r| {
            if (!std.mem.eql(u8, r.parser, parser_name)) continue;
            sum += r.throughput_mb_s;
            count += 1;
        }
        out[idx] = .{
            .parser = parser_name,
            .avg_mb_s = if (count == 0) 0.0 else sum / @as(f64, @floatFromInt(count)),
        };
    }

    var i: usize = 1;
    while (i < out.len) : (i += 1) {
        var j = i;
        while (j > 0 and out[j - 1].avg_mb_s < out[j].avg_mb_s) : (j -= 1) {
            std.mem.swap(AverageThroughputRow, &out[j - 1], &out[j]);
        }
    }

    return out;
}

test "evaluateGateRows records best external parser" {
    const alloc = std.testing.allocator;
    const profile = Profile{
        .name = "test",
        .fixtures = &[_]FixtureCase{
            .{ .name = "x.xml", .iterations = 1, .is_real = true },
        },
    };
    var sample_a = [_]u64{1};
    var sample_b = [_]u64{1};
    var sample_c = [_]u64{1};
    const rows = [_]ParseResult{
        .{ .parser = "ours-turbo", .fixture = "x.xml", .is_real = true, .iterations = 1, .samples_ns = &sample_a, .median_ns = 1, .throughput_mb_s = 120.0 },
        .{ .parser = "pugixml", .fixture = "x.xml", .is_real = true, .iterations = 1, .samples_ns = &sample_b, .median_ns = 1, .throughput_mb_s = 110.0 },
        .{ .parser = "rapidxml", .fixture = "x.xml", .is_real = true, .iterations = 1, .samples_ns = &sample_c, .median_ns = 1, .throughput_mb_s = 100.0 },
    };

    const gates = try evaluateGateRows(alloc, profile, &rows);
    defer freeGateRows(alloc, gates);

    try std.testing.expectEqual(@as(usize, 1), gates.len);
    try std.testing.expectEqualStrings("pugixml", gates[0].best_external_parser);
    try std.testing.expect(gates[0].pass);
}

fn findParseResult(parse_results: []const ParseResult, parser_name: []const u8, fixture_name: []const u8) ?*const ParseResult {
    for (parse_results) |*r| {
        if (std.mem.eql(u8, r.parser, parser_name) and std.mem.eql(u8, r.fixture, fixture_name)) return r;
    }
    return null;
}

fn updateFileSection(
    io: std.Io,
    alloc: std.mem.Allocator,
    path: []const u8,
    start_marker: []const u8,
    end_marker: []const u8,
    replacement: []const u8,
) !void {
    // Mirror zhtmlparser-style README snapshots by replacing only the
    // auto-generated section between stable markers.
    const current = try common.readFileAlloc(io, alloc, path);
    defer alloc.free(current);

    const start = std.mem.indexOf(u8, current, start_marker) orelse return error.ReadmeBenchMarkersMissing;
    const after_start = start + start_marker.len;
    const end = std.mem.indexOfPos(u8, current, after_start, end_marker) orelse return error.ReadmeBenchMarkersMissing;

    var out = std.ArrayList(u8).empty;
    defer out.deinit(alloc);
    try out.appendSlice(alloc, current[0..after_start]);
    try out.appendSlice(alloc, "\n\n");
    try out.appendSlice(alloc, replacement);
    if (replacement.len == 0 or replacement[replacement.len - 1] != '\n') try out.append(alloc, '\n');
    if (current[end - 1] != '\n') try out.append(alloc, '\n');
    try out.appendSlice(alloc, current[end..]);

    if (!std.mem.eql(u8, out.items, current)) {
        try common.writeFile(io, path, out.items);
        std.debug.print("wrote {s} benchmark summary\n", .{path});
    } else {
        std.debug.print("{s} benchmark summary already up-to-date\n", .{path});
    }
}

fn renderReadmeAutoSummary(
    alloc: std.mem.Allocator,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_gate_rows: []const StreamGateRow,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    const averages = try makeAverageThroughputRows(alloc, parse_results);
    defer alloc.free(averages);

    try w.print("Source: `bench/results/latest.json` (`{s}` profile).\n\n", .{profile_name});
    try w.writeAll("### Parse Throughput (Average Across Fixtures)\n\n");
    try w.writeAll("```text\n");

    var leader: f64 = 0.0;
    var max_name_len: usize = 0;
    for (averages) |row| {
        leader = @max(leader, row.avg_mb_s);
        max_name_len = @max(max_name_len, row.parser.len);
    }

    for (averages) |row| {
        const pct = if (leader > 0.0) (row.avg_mb_s / leader) * 100.0 else 0.0;
        const width: usize = 20;
        const filled = if (leader > 0.0)
            @min(width, @max(@as(usize, @intFromFloat(@round((row.avg_mb_s / leader) * @as(f64, @floatFromInt(width))))), @as(usize, 1)))
        else
            @as(usize, 0);
        try w.writeAll(row.parser);
        for (0..max_name_len - row.parser.len) |_| try w.writeByte(' ');
        try w.writeAll(" │");
        for (0..filled) |_| try w.writeAll("█");
        for (0..(width - filled)) |_| try w.writeAll("░");
        try w.print("│ {d:.2} MB/s ({d:.2}%)\n", .{ row.avg_mb_s, pct });
    }
    try w.writeAll("```\n\n");

    try w.writeAll("### Stable Gate Snapshot\n\n");
    try w.writeAll("| Profile | Passed | Rule |\n");
    try w.writeAll("|---|---:|---|\n");
    const pass_count: usize = blk: {
        var count: usize = 0;
        for (gate_rows) |g| {
            if (g.pass) count += 1;
        }
        break :blk count;
    };
    try w.print("| `{s}` | {d}/{d} | `ours-turbo >= max(pugixml, rapidxml)` |\n", .{
        profile_name,
        pass_count,
        gate_rows.len,
    });
    const stream_pass_count: usize = blk: {
        var count: usize = 0;
        for (stream_gate_rows) |g| {
            if (g.pass) count += 1;
        }
        break :blk count;
    };
    try w.print("| `{s}` | {d}/{d} | `stream-turbo >= ours-turbo && stream-strict >= ours-strict` |\n", .{
        profile_name,
        stream_pass_count,
        stream_gate_rows.len,
    });

    return out.toOwnedSlice();
}

fn renderBenchReadmeSnapshot(
    alloc: std.mem.Allocator,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_gate_rows: []const StreamGateRow,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("Source: `bench/results/latest.json` (`{s}` profile).\n\n", .{profile_name});
    try w.writeAll("## Latest Benchmark Snapshot\n\n");
    try w.writeAll("### Parse Throughput Comparison (MB/s)\n\n");
    try w.writeAll("| Fixture | ours-turbo | ours-strict | stream-turbo | stream-strict | pugixml | rapidxml |\n");
    try w.writeAll("|---|---:|---:|---:|---:|---:|---:|\n");

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

    for (fixtures.items) |fixture_name| {
        try w.print("| `{s}` | ", .{fixture_name});
        if (findParseResult(parse_results, "ours-turbo", fixture_name)) |r| {
            try w.print("{d:.2}", .{r.throughput_mb_s});
        } else try w.writeAll("-");
        try w.writeAll(" | ");
        if (findParseResult(parse_results, "ours-strict", fixture_name)) |r| {
            try w.print("{d:.2}", .{r.throughput_mb_s});
        } else try w.writeAll("-");
        try w.writeAll(" | ");
        if (findParseResult(parse_results, "stream-turbo", fixture_name)) |r| {
            try w.print("{d:.2}", .{r.throughput_mb_s});
        } else try w.writeAll("-");
        try w.writeAll(" | ");
        if (findParseResult(parse_results, "stream-strict", fixture_name)) |r| {
            try w.print("{d:.2}", .{r.throughput_mb_s});
        } else try w.writeAll("-");
        try w.writeAll(" | ");
        if (findParseResult(parse_results, "pugixml", fixture_name)) |r| {
            try w.print("{d:.2}", .{r.throughput_mb_s});
        } else try w.writeAll("-");
        try w.writeAll(" | ");
        if (findParseResult(parse_results, "rapidxml", fixture_name)) |r| {
            try w.print("{d:.2}", .{r.throughput_mb_s});
        } else try w.writeAll("-");
        try w.writeAll(" |\n");
    }

    try w.writeAll("\n### Stable Gates\n\n");
    try w.writeAll("| Fixture | ours-turbo | best external | ours/best-ext | Result |\n");
    try w.writeAll("|---|---:|---|---:|---|\n");
    for (gate_rows) |g| {
        try w.print(
            "| `{s}` | {d:.2} | `{s}` {d:.2} | {d:.3} | {s} |\n",
            .{
                g.fixture,
                g.ours_turbo_mb_s,
                g.best_external_parser,
                g.best_external_mb_s,
                g.external_ratio,
                if (g.pass) "PASS" else "FAIL",
            },
        );
    }

    if (stream_gate_rows.len != 0) {
        try w.writeAll("\n### Streaming Gates\n\n");
        try w.writeAll("| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours | Result |\n");
        try w.writeAll("|---|---:|---:|---:|---:|---:|---:|---|\n");
        for (stream_gate_rows) |g| {
            try w.print(
                "| `{s}` | {d:.2} | {d:.2} | {d:.3} | {d:.2} | {d:.2} | {d:.3} | {s} |\n",
                .{
                    g.fixture,
                    g.stream_turbo_mb_s,
                    g.dom_turbo_mb_s,
                    g.turbo_ratio,
                    g.stream_strict_mb_s,
                    g.dom_strict_mb_s,
                    g.strict_ratio,
                    if (g.pass) "PASS" else "FAIL",
                },
            );
        }
    }

    try w.writeAll("\nFor the full terminal-style report:\n");
    try w.writeAll("- `bench/results/latest.md`\n");
    try w.writeAll("- `bench/results/latest.json`\n");
    return out.toOwnedSlice();
}

fn updateBenchmarkReadmes(
    io: std.Io,
    alloc: std.mem.Allocator,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_gate_rows: []const StreamGateRow,
) !void {
    const root_summary = try renderReadmeAutoSummary(alloc, profile_name, parse_results, gate_rows, stream_gate_rows);
    defer alloc.free(root_summary);
    try updateFileSection(io, alloc, "README.md", ReadmeSummaryStartMarker, ReadmeSummaryEndMarker, root_summary);

    const bench_snapshot = try renderBenchReadmeSnapshot(alloc, profile_name, parse_results, gate_rows, stream_gate_rows);
    defer alloc.free(bench_snapshot);
    try updateFileSection(io, alloc, "bench/README.md", BenchReadmeSnapshotStartMarker, BenchReadmeSnapshotEndMarker, bench_snapshot);
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

fn writeMarkdown(
    io: std.Io,
    alloc: std.mem.Allocator,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_gate_rows: []const StreamGateRow,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("# ZXML Benchmark Results\n\nGenerated (unix): {d}\n\nProfile: `{s}`\n\n", .{ common.nowUnix(io), profile_name });

    try w.writeAll("## Parse Throughput\n\n");
    try w.writeAll("| Fixture | Parser | Throughput (MB/s) | Median Time (ms) | Iterations |\n");
    try w.writeAll("|---|---|---:|---:|---:|\n");
    for (parse_results) |r| {
        const median_ms = @as(f64, @floatFromInt(r.median_ns)) / 1_000_000.0;
        try w.print("| {s} | {s} | {d:.2} | {d:.2} | {d} |\n", .{ r.fixture, r.parser, r.throughput_mb_s, median_ms, r.iterations });
    }

    if (gate_rows.len != 0) {
        try w.writeAll("\n## Stable Gates\n\n");
        try w.writeAll("| Fixture | ours-turbo | pugixml | rapidxml | best external | ours/best-ext | Result |\n");
        try w.writeAll("|---|---:|---:|---:|---|---:|---|\n");
        for (gate_rows) |g| {
            try w.print(
                "| {s} | {d:.2} | {d:.2} | {d:.2} | {s} {d:.2} | {d:.3} | {s} |\n",
                .{
                    g.fixture,
                    g.ours_turbo_mb_s,
                    g.pugixml_mb_s,
                    g.rapidxml_mb_s,
                    g.best_external_parser,
                    g.best_external_mb_s,
                    g.external_ratio,
                    if (g.pass) "PASS" else "FAIL",
                },
            );
        }
    }

    if (stream_gate_rows.len != 0) {
        try w.writeAll("\n## Streaming Gates\n\n");
        try w.writeAll("| Fixture | stream-turbo | ours-turbo | stream/ours | stream-strict | ours-strict | stream/ours | Result |\n");
        try w.writeAll("|---|---:|---:|---:|---:|---:|---:|---|\n");
        for (stream_gate_rows) |g| {
            try w.print(
                "| {s} | {d:.2} | {d:.2} | {d:.3} | {d:.2} | {d:.2} | {d:.3} | {s} |\n",
                .{
                    g.fixture,
                    g.stream_turbo_mb_s,
                    g.dom_turbo_mb_s,
                    g.turbo_ratio,
                    g.stream_strict_mb_s,
                    g.dom_strict_mb_s,
                    g.strict_ratio,
                    if (g.pass) "PASS" else "FAIL",
                },
            );
        }
    }

    return out.toOwnedSlice();
}

fn writeTerminalReport(
    io: std.Io,
    alloc: std.mem.Allocator,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_gate_rows: []const StreamGateRow,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("ZXML Benchmark Results\nGenerated (unix): {d}\nProfile: {s}\n\n", .{ common.nowUnix(io), profile_name });

    // Group by fixture first so terminal output stays easy to compare in-place.
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
            "pugixml",
            "rapidxml",
            "best external",
            "ours/best-ext",
            "Result",
        };
        const gate_header_align = [_]bool{ false, false, false, false, false, false, false };
        const gate_align = [_]bool{ false, true, true, true, false, true, false };
        var gate_widths = [_]usize{
            gate_headers[0].len,
            gate_headers[1].len,
            gate_headers[2].len,
            gate_headers[3].len,
            gate_headers[4].len,
            gate_headers[5].len,
            gate_headers[6].len,
        };

        for (gate_rows) |g| {
            gate_widths[0] = maxUsize(gate_widths[0], g.fixture.len);

            var ours_buf: [32]u8 = undefined;
            const ours = try std.fmt.bufPrint(&ours_buf, "{d:.2}", .{g.ours_turbo_mb_s});
            gate_widths[1] = maxUsize(gate_widths[1], ours.len);

            var pugixml_buf: [32]u8 = undefined;
            const pugixml = try std.fmt.bufPrint(&pugixml_buf, "{d:.2}", .{g.pugixml_mb_s});
            gate_widths[2] = maxUsize(gate_widths[2], pugixml.len);

            var rapidxml_buf: [32]u8 = undefined;
            const rapidxml = try std.fmt.bufPrint(&rapidxml_buf, "{d:.2}", .{g.rapidxml_mb_s});
            gate_widths[3] = maxUsize(gate_widths[3], rapidxml.len);

            var best_buf: [64]u8 = undefined;
            const best = try std.fmt.bufPrint(&best_buf, "{s} {d:.2}", .{ g.best_external_parser, g.best_external_mb_s });
            gate_widths[4] = maxUsize(gate_widths[4], best.len);

            var ratio_buf: [32]u8 = undefined;
            const ratio = try std.fmt.bufPrint(&ratio_buf, "{d:.3}", .{g.external_ratio});
            gate_widths[5] = maxUsize(gate_widths[5], ratio.len);

            const result = if (g.pass) "PASS" else "FAIL";
            gate_widths[6] = maxUsize(gate_widths[6], result.len);
        }

        try writeTableBorder(w, &gate_widths);
        try writeTableRow(w, &gate_headers, &gate_widths, &gate_header_align);
        try writeTableBorder(w, &gate_widths);

        var pass_count: usize = 0;
        for (gate_rows) |g| {
            if (g.pass) pass_count += 1;

            var ours_buf: [32]u8 = undefined;
            const ours = try std.fmt.bufPrint(&ours_buf, "{d:.2}", .{g.ours_turbo_mb_s});

            var pugixml_buf: [32]u8 = undefined;
            const pugixml = try std.fmt.bufPrint(&pugixml_buf, "{d:.2}", .{g.pugixml_mb_s});

            var rapidxml_buf: [32]u8 = undefined;
            const rapidxml = try std.fmt.bufPrint(&rapidxml_buf, "{d:.2}", .{g.rapidxml_mb_s});

            var best_buf: [64]u8 = undefined;
            const best = try std.fmt.bufPrint(&best_buf, "{s} {d:.2}", .{ g.best_external_parser, g.best_external_mb_s });

            var ratio_buf: [32]u8 = undefined;
            const ratio = try std.fmt.bufPrint(&ratio_buf, "{d:.3}", .{g.external_ratio});

            const row = [_][]const u8{
                g.fixture,
                ours,
                pugixml,
                rapidxml,
                best,
                ratio,
                if (g.pass) "PASS" else "FAIL",
            };
            try writeTableRow(w, &row, &gate_widths, &gate_align);
        }
        try writeTableBorder(w, &gate_widths);
        try w.print("Gate Summary: {d}/{d} passed\n", .{ pass_count, gate_rows.len });
    }

    if (stream_gate_rows.len != 0) {
        try w.writeAll("\nStreaming Gates\n");
        const headers = [_][]const u8{
            "Fixture",
            "stream-turbo",
            "ours-turbo",
            "stream/ours",
            "stream-strict",
            "ours-strict",
            "stream/ours",
            "Result",
        };
        const header_align = [_]bool{ false, false, false, false, false, false, false, false };
        const row_align = [_]bool{ false, true, true, true, true, true, true, false };
        var widths = [_]usize{
            headers[0].len,
            headers[1].len,
            headers[2].len,
            headers[3].len,
            headers[4].len,
            headers[5].len,
            headers[6].len,
            headers[7].len,
        };

        for (stream_gate_rows) |g| {
            widths[0] = maxUsize(widths[0], g.fixture.len);
            inline for (&.{ g.stream_turbo_mb_s, g.dom_turbo_mb_s, g.turbo_ratio, g.stream_strict_mb_s, g.dom_strict_mb_s, g.strict_ratio }, 1..) |value, col| {
                var buf: [32]u8 = undefined;
                const txt = if (col == 3 or col == 6)
                    try std.fmt.bufPrint(&buf, "{d:.3}", .{value})
                else
                    try std.fmt.bufPrint(&buf, "{d:.2}", .{value});
                widths[col] = maxUsize(widths[col], txt.len);
            }
            widths[7] = maxUsize(widths[7], if (g.pass) 4 else 4);
        }

        try writeTableBorder(w, &widths);
        try writeTableRow(w, &headers, &widths, &header_align);
        try writeTableBorder(w, &widths);
        var pass_count: usize = 0;
        for (stream_gate_rows) |g| {
            if (g.pass) pass_count += 1;
            var stream_turbo_buf: [32]u8 = undefined;
            const stream_turbo = try std.fmt.bufPrint(&stream_turbo_buf, "{d:.2}", .{g.stream_turbo_mb_s});
            var dom_turbo_buf: [32]u8 = undefined;
            const dom_turbo = try std.fmt.bufPrint(&dom_turbo_buf, "{d:.2}", .{g.dom_turbo_mb_s});
            var turbo_ratio_buf: [32]u8 = undefined;
            const turbo_ratio = try std.fmt.bufPrint(&turbo_ratio_buf, "{d:.3}", .{g.turbo_ratio});
            var stream_strict_buf: [32]u8 = undefined;
            const stream_strict = try std.fmt.bufPrint(&stream_strict_buf, "{d:.2}", .{g.stream_strict_mb_s});
            var dom_strict_buf: [32]u8 = undefined;
            const dom_strict = try std.fmt.bufPrint(&dom_strict_buf, "{d:.2}", .{g.dom_strict_mb_s});
            var strict_ratio_buf: [32]u8 = undefined;
            const strict_ratio = try std.fmt.bufPrint(&strict_ratio_buf, "{d:.3}", .{g.strict_ratio});
            const row = [_][]const u8{
                g.fixture,
                stream_turbo,
                dom_turbo,
                turbo_ratio,
                stream_strict,
                dom_strict,
                strict_ratio,
                if (g.pass) "PASS" else "FAIL",
            };
            try writeTableRow(w, &row, &widths, &row_align);
        }
        try writeTableBorder(w, &widths);
        try w.print("Streaming Gate Summary: {d}/{d} passed\n", .{ pass_count, stream_gate_rows.len });
    }

    return out.toOwnedSlice();
}

fn writeJson(
    io: std.Io,
    alloc: std.mem.Allocator,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_gate_rows: []const StreamGateRow,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("{{\n  \"generated_unix\": {d},\n  \"profile\": \"{s}\",\n  \"parse_results\": [\n", .{ common.nowUnix(io), profile_name });
    for (parse_results, 0..) |r, i| {
        try w.print(
            "    {{\"parser\":\"{s}\",\"fixture\":\"{s}\",\"is_real\":{s},\"iterations\":{d},\"median_ns\":{d},\"throughput_mb_s\":{d:.6}}}{s}\n",
            .{ r.parser, r.fixture, if (r.is_real) "true" else "false", r.iterations, r.median_ns, r.throughput_mb_s, if (i + 1 == parse_results.len) "" else "," },
        );
    }
    try w.writeAll("  ],\n  \"gates\": [\n");
    for (gate_rows, 0..) |g, i| {
        try w.print(
            "    {{\"fixture\":\"{s}\",\"is_real\":{s},\"ours_turbo_mb_s\":{d:.6},\"pugixml_mb_s\":{d:.6},\"rapidxml_mb_s\":{d:.6},\"best_external_parser\":\"{s}\",\"best_external_mb_s\":{d:.6},\"external_ratio\":{d:.6},\"pass\":{s}}}{s}\n",
            .{
                g.fixture,
                if (g.is_real) "true" else "false",
                g.ours_turbo_mb_s,
                g.pugixml_mb_s,
                g.rapidxml_mb_s,
                g.best_external_parser,
                g.best_external_mb_s,
                g.external_ratio,
                if (g.pass) "true" else "false",
                if (i + 1 == gate_rows.len) "" else ",",
            },
        );
    }
    try w.writeAll("  ],\n  \"stream_gates\": [\n");
    for (stream_gate_rows, 0..) |g, i| {
        try w.print(
            "    {{\"fixture\":\"{s}\",\"is_real\":{s},\"dom_turbo_mb_s\":{d:.6},\"stream_turbo_mb_s\":{d:.6},\"turbo_ratio\":{d:.6},\"dom_strict_mb_s\":{d:.6},\"stream_strict_mb_s\":{d:.6},\"strict_ratio\":{d:.6},\"pass\":{s}}}{s}\n",
            .{
                g.fixture,
                if (g.is_real) "true" else "false",
                g.dom_turbo_mb_s,
                g.stream_turbo_mb_s,
                g.turbo_ratio,
                g.dom_strict_mb_s,
                g.stream_strict_mb_s,
                g.strict_ratio,
                if (g.pass) "true" else "false",
                if (i + 1 == stream_gate_rows.len) "" else ",",
            },
        );
    }
    try w.writeAll("  ]\n}\n");

    return out.toOwnedSlice();
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
    if (root != .object) return error.InvalidBaseline;
    const parse_results = root.object.get("parse_results") orelse return error.InvalidBaseline;
    if (parse_results != .array) return error.InvalidBaseline;
    for (parse_results.array.items) |item| {
        if (item != .object) return error.InvalidBaseline;
        const obj = item.object;
        const parser_name = obj.get("parser") orelse return error.InvalidBaseline;
        const fixture_name = obj.get("fixture") orelse return error.InvalidBaseline;
        const throughput = obj.get("throughput_mb_s") orelse return error.InvalidBaseline;
        if (parser_name != .string or fixture_name != .string) return error.InvalidBaseline;
        if (throughput != .float and throughput != .integer) return error.InvalidBaseline;

        const key = try std.fmt.allocPrint(alloc, "{s}|{s}", .{ parser_name.string, fixture_name.string });
        const val: f64 = switch (throughput) {
            .float => throughput.float,
            .integer => @floatFromInt(throughput.integer),
            else => unreachable,
        };
        if (!std.math.isFinite(val) or val < 0) {
            alloc.free(key);
            return error.InvalidBaseline;
        }
        errdefer alloc.free(key);
        const gop = try map.getOrPut(key);
        if (gop.found_existing) {
            alloc.free(key);
        } else {
            gop.key_ptr.* = key;
        }
        gop.value_ptr.* = val;
    }

    return map;
}

test "parseBaseline validates shape and replaces duplicate measurements" {
    const alloc = std.testing.allocator;
    var map = try parseBaseline(alloc, "{\"parse_results\":[{\"parser\":\"ours-turbo\",\"fixture\":\"x.xml\",\"throughput_mb_s\":1.5},{\"parser\":\"ours-turbo\",\"fixture\":\"x.xml\",\"throughput_mb_s\":2}]}");
    defer freeBaselineMap(alloc, &map);
    try std.testing.expectEqual(@as(usize, 1), map.count());
    try std.testing.expectEqual(@as(f64, 2.0), map.get("ours-turbo|x.xml").?);

    try std.testing.expectError(error.InvalidBaseline, parseBaseline(alloc, "[]"));
    try std.testing.expectError(error.InvalidBaseline, parseBaseline(alloc, "{}"));
    try std.testing.expectError(error.InvalidBaseline, parseBaseline(alloc, "{\"parse_results\":{}}"));
    try std.testing.expectError(error.InvalidBaseline, parseBaseline(alloc, "{\"parse_results\":[{\"parser\":\"ours-turbo\",\"fixture\":\"x.xml\"}]}"));
    try std.testing.expectError(error.InvalidBaseline, parseBaseline(alloc, "{\"parse_results\":[{\"parser\":1,\"fixture\":\"x.xml\",\"throughput_mb_s\":1}]}"));
    try std.testing.expectError(error.InvalidBaseline, parseBaseline(alloc, "{\"parse_results\":[{\"parser\":\"ours-turbo\",\"fixture\":\"x.xml\",\"throughput_mb_s\":-1}]}"));
}

fn freeBaselineMap(alloc: std.mem.Allocator, map: *std.StringHashMap(f64)) void {
    var it = map.iterator();
    while (it.next()) |kv| {
        alloc.free(kv.key_ptr.*);
    }
    map.deinit();
}

fn runBenchmarks(io: std.Io, alloc: std.mem.Allocator, args: []const []const u8) !void {
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

    try common.ensureDir(io, RESULTS_DIR);
    try setupParsers(io, alloc);
    try setupFixtures(io, alloc, false);
    try ensureExternalParsersBuilt(io, alloc);
    try buildRunners(io, alloc);

    var parse_results = std.ArrayList(ParseResult).empty;
    defer {
        for (parse_results.items) |*r| freeParseResult(alloc, r);
        parse_results.deinit(alloc);
    }

    for (profile.fixtures) |fx| {
        for (parse_parsers) |p| {
            std.debug.print("running parse: parser={s} fixture={s} iterations={d}\n", .{ p, fx.name, fx.iterations });
            var result = try runParseBench(io, alloc, p, fx);
            errdefer freeParseResult(alloc, &result);
            try parse_results.append(alloc, result);
        }
    }

    const gate_rows = try evaluateGateRows(alloc, profile, parse_results.items);
    defer freeGateRows(alloc, gate_rows);
    const stream_gate_rows = try evaluateStreamGateRows(alloc, profile, parse_results.items);
    defer freeStreamGateRows(alloc, stream_gate_rows);

    const md = try writeMarkdown(io, alloc, profile.name, parse_results.items, gate_rows, stream_gate_rows);
    defer alloc.free(md);
    try common.writeFile(io, RESULTS_DIR ++ "/latest.md", md);

    const terminal = try writeTerminalReport(io, alloc, profile.name, parse_results.items, gate_rows, stream_gate_rows);
    defer alloc.free(terminal);

    const json = try writeJson(io, alloc, profile.name, parse_results.items, gate_rows, stream_gate_rows);
    defer alloc.free(json);
    try common.writeFile(io, RESULTS_DIR ++ "/latest.json", json);
    try updateBenchmarkReadmes(io, alloc, profile.name, parse_results.items, gate_rows, stream_gate_rows);

    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll("\n");
    try stdout.writeAll(terminal);
    try stdout.writeAll("\n");
    try stdout.flush();

    const baseline_default = try std.fmt.allocPrint(alloc, RESULTS_DIR ++ "/baseline_{s}.json", .{profile.name});
    defer alloc.free(baseline_default);
    const baseline = baseline_path orelse baseline_default;

    if (write_baseline) {
        try common.writeFile(io, baseline, json);
        std.debug.print("wrote baseline {s}\n", .{baseline});
    }

    var failed = false;

    if (std.mem.eql(u8, profile.name, "stable")) {
        for (gate_rows) |g| {
            if (!g.pass) {
                failed = true;
                std.debug.print(
                    "gate fail: {s} ours={d:.2} best={s} {d:.2} ratio={d:.3}\n",
                    .{ g.fixture, g.ours_turbo_mb_s, g.best_external_parser, g.best_external_mb_s, g.external_ratio },
                );
            }
        }
        for (stream_gate_rows) |g| {
            if (!g.pass) {
                failed = true;
                std.debug.print(
                    "stream gate fail: {s} stream-turbo={d:.2} dom-turbo={d:.2} turbo-ratio={d:.3} stream-strict={d:.2} dom-strict={d:.2} strict-ratio={d:.3}\n",
                    .{ g.fixture, g.stream_turbo_mb_s, g.dom_turbo_mb_s, g.turbo_ratio, g.stream_strict_mb_s, g.dom_strict_mb_s, g.strict_ratio },
                );
            }
        }
    }

    if (common.fileExists(io, baseline)) {
        const baseline_bytes = try common.readFileAlloc(io, alloc, baseline);
        defer alloc.free(baseline_bytes);

        var base_map = try parseBaseline(alloc, baseline_bytes);
        defer freeBaselineMap(alloc, &base_map);

        for (parse_results.items) |r| {
            if (!std.mem.startsWith(u8, r.parser, "ours-")) continue;
            const key = try std.fmt.allocPrint(alloc, "{s}|{s}", .{ r.parser, r.fixture });
            defer alloc.free(key);
            const base = base_map.get(key) orelse return error.InvalidBaseline;
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
        \\  zxml-tools setup-parsers
        \\  zxml-tools setup-fixtures [--refresh]
        \\  zxml-tools run-benchmarks [--profile quick|stable] [--baseline path] [--write-baseline]
        \\  zxml-tools run-conformance [--suite path]...
        \\
    , .{});
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(alloc);

    var it = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer it.deinit();
    while (it.next()) |arg| {
        try args.append(alloc, try alloc.dupe(u8, arg));
    }

    if (args.items.len < 2) {
        usage();
        return error.InvalidArguments;
    }

    const cmd = args.items[1];
    if (std.mem.eql(u8, cmd, "--help") or std.mem.eql(u8, cmd, "help")) {
        usage();
        return;
    }

    if (std.mem.eql(u8, cmd, "setup-parsers")) {
        try setupParsers(init.io, alloc);
        return;
    }

    if (std.mem.eql(u8, cmd, "setup-fixtures")) {
        var refresh = false;
        var i: usize = 2;
        while (i < args.items.len) : (i += 1) {
            if (std.mem.eql(u8, args.items[i], "--refresh")) refresh = true else return error.InvalidArguments;
        }
        try setupFixtures(init.io, alloc, refresh);
        return;
    }

    if (std.mem.eql(u8, cmd, "run-benchmarks")) {
        try runBenchmarks(init.io, alloc, args.items[2..]);
        return;
    }

    if (std.mem.eql(u8, cmd, "run-conformance")) {
        try conformance.runConformance(init.io, alloc, args.items[2..]);
        return;
    }

    usage();
    return error.InvalidArguments;
}

test "benchmark gates reject missing parser rows" {
    const alloc = std.testing.allocator;
    const fixtures = [_]FixtureCase{.{ .name = "fixture.xml", .iterations = 1, .is_real = true }};
    const profile = Profile{ .name = "test", .fixtures = &fixtures };
    var samples = [_]u64{1};
    const incomplete = [_]ParseResult{.{
        .parser = "ours-turbo",
        .fixture = "fixture.xml",
        .is_real = true,
        .iterations = 1,
        .samples_ns = &samples,
        .median_ns = 1,
        .throughput_mb_s = 1.0,
    }};

    try std.testing.expectError(error.MissingBenchmarkResult, evaluateGateRows(alloc, profile, &incomplete));
    try std.testing.expectError(error.MissingBenchmarkResult, evaluateStreamGateRows(alloc, profile, &incomplete));
}
