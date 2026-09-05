const std = @import("std");
const common = @import("common.zig");
const conformance = @import("conformance.zig");

const REPO_ROOT = ".";
const BUILD_DIR = "bench/build";
const BIN_DIR = "bench/build/bin";
const TMP_SCRATCH_DIR = BUILD_DIR ++ "/tmp";
const RESULTS_DIR = "bench/results";
const STABLE_RESUME_PATH = RESULTS_DIR ++ "/stable.resume.json";
const FIXTURES_DIR = "bench/fixtures";
const PARSERS_DIR = "bench/parsers";
const pugixml_revision = "27b68329de32cf9c601ca8eb6c588fd639960c40";
const min_sample_ns: u64 = 20_000_000;
const target_sample_ns: u64 = 40_000_000;
const max_sample_ns: u64 = 80_000_000;
const ReadmeSummaryStartMarker = "<!-- README_AUTO_SUMMARY:START -->";
const ReadmeSummaryEndMarker = "<!-- README_AUTO_SUMMARY:END -->";
const BenchReadmeSnapshotStartMarker = "<!-- BENCH_README_AUTO_SNAPSHOT:START -->";
const BenchReadmeSnapshotEndMarker = "<!-- BENCH_README_AUTO_SNAPSHOT:END -->";
const max_opaque_cdata_ratio = 0.90;

const repeats: usize = 5;
const benchmark_methodology_version: usize = 3;
const interleaved_build_seed: u64 = 23_063;

const documentation_files = [_][]const u8{
    "README.md",
    "CONTRIBUTING.md",
    "SECURITY.md",
    "bench/README.md",
};

const tool_command_names = [_][]const u8{
    "setup-parsers",
    "setup-fixtures",
    "run-benchmarks",
    "compare-worktrees",
    "run-conformance",
    "docs-check",
    "examples-check",
};

const parse_parsers = [_][]const u8{
    "ours-validated",
    "ours-permissive",
    "stream-validated",
    "stream-permissive",
    "pugixml",
    "rapidxml",
};

const validated_regression_parsers = [_][]const u8{
    "ours-validated",
    "stream-validated",
};

const validated_regression_reference_fixture = "synthetic_entities.xml";
const validated_regression_min_reference_ratio: f64 = 1.25;

const FixtureCase = struct {
    name: []const u8,
    iterations: usize,
    is_real: bool,
    validated_valid: bool = true,
};

const Profile = struct {
    name: []const u8,
    fixtures: []const FixtureCase,
};

const BenchmarkEnvironment = struct {
    os: []const u8,
    architecture: []const u8,
    cpu_model: []const u8,
    cpu_scaling: []const u8,
    cpu_min_mhz: []const u8,
    cpu_max_mhz: []const u8,
    zig_version: []const u8,
    cxx_driver: []const u8,

    fn deinit(self: BenchmarkEnvironment, alloc: std.mem.Allocator) void {
        inline for (std.meta.fields(BenchmarkEnvironment)) |field| {
            alloc.free(@field(self, field.name));
        }
    }
};

const LscpuEntry = struct {
    field: []const u8,
    data: []const u8,
};

const LscpuOutput = struct {
    lscpu: []const LscpuEntry,
};

const BenchmarkResumeRow = struct {
    parser: []const u8,
    fixture: []const u8,
    is_real: bool,
    iterations: usize,
    samples_ns: []const u64,
    median_ns: u64,
    throughput_mb_s: f64,
};

const BenchmarkResumeState = struct {
    profile: []const u8,
    methodology_version: usize,
    source_head: []const u8,
    os: []const u8,
    architecture: []const u8,
    cpu_model: []const u8,
    zig_version: []const u8,
    cxx_driver: []const u8,
    parse_results: []const BenchmarkResumeRow,
};

const BenchmarkResumeContext = struct {
    source_head: []const u8,
    environment: *const BenchmarkEnvironment,
};

const smoke_fixtures = [_]FixtureCase{
    .{ .name = "synthetic_two_attr.xml", .iterations = 1, .is_real = false },
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
    .{ .name = "synthetic_tiny_text.xml", .iterations = 160, .is_real = false },
    .{ .name = "synthetic_two_attr.xml", .iterations = 140, .is_real = false },
    .{ .name = "synthetic_attrs8.xml", .iterations = 100, .is_real = false },
    .{ .name = "synthetic_pretty_indented.xml", .iterations = 100, .is_real = false },
    .{ .name = "synthetic_attr_count_mix.xml", .iterations = 90, .is_real = false },
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
    .{ .name = "transitions.xml", .iterations = 260, .is_real = true, .validated_valid = false },
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
    .{ .name = "synthetic_tiny_empty.xml", .iterations = 360, .is_real = false },
    .{ .name = "synthetic_tiny_text.xml", .iterations = 340, .is_real = false },
    .{ .name = "synthetic_one_attr.xml", .iterations = 300, .is_real = false },
    .{ .name = "synthetic_two_attr.xml", .iterations = 280, .is_real = false },
    .{ .name = "synthetic_attrs4.xml", .iterations = 240, .is_real = false },
    .{ .name = "synthetic_attrs8.xml", .iterations = 200, .is_real = false },
    .{ .name = "synthetic_single_quotes.xml", .iterations = 240, .is_real = false },
    .{ .name = "synthetic_unicode_names.xml", .iterations = 180, .is_real = false },
    .{ .name = "synthetic_pretty_indented.xml", .iterations = 200, .is_real = false },
    .{ .name = "synthetic_crlf_pretty.xml", .iterations = 200, .is_real = false },
    .{ .name = "synthetic_token_whitespace_mix.xml", .iterations = 200, .is_real = false },
    .{ .name = "synthetic_attr_count_mix.xml", .iterations = 160, .is_real = false },
};

// Pathological workloads do not belong in headline averages or external gates.
// Keep them in a mode-specific lane that runs only the implementations whose
// behavior they stress. The generated data remains available for ad-hoc work.
const validated_regression_fixtures = [_]FixtureCase{
    .{ .name = "synthetic_doctype_entities.xml", .iterations = 80, .is_real = false },
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
    ours_permissive_mb_s: f64,
    pugixml_mb_s: f64,
    rapidxml_mb_s: f64,
    best_external_parser: []const u8,
    best_external_mb_s: f64,
    /// Ratio against the faster external DOM parser for this fixture.
    external_ratio: f64,
    pass: bool,
};

const StreamComparisonRow = struct {
    fixture: []const u8,
    is_real: bool,
    dom_permissive_mb_s: f64,
    stream_permissive_mb_s: f64,
    permissive_ratio: f64,
    dom_validated_mb_s: f64,
    stream_validated_mb_s: f64,
    validated_ratio: f64,
};

const ValidatedRegressionCheck = struct {
    parser: []const u8,
    fixture: []const u8,
    reference_fixture: []const u8,
    throughput_mb_s: f64,
    reference_mb_s: f64,
    reference_ratio: f64,
    pass: bool,
};

fn getProfile(name: []const u8) !Profile {
    if (std.mem.eql(u8, name, "smoke")) return .{ .name = "smoke", .fixtures = &smoke_fixtures };
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
        const init = [_][]const u8{ "git", "init", pugixml_dir };
        try common.runInherit(io, alloc, &init, REPO_ROOT);
        const remote = [_][]const u8{ "git", "-C", pugixml_dir, "remote", "add", "origin", "https://github.com/zeux/pugixml.git" };
        try common.runInherit(io, alloc, &remote, REPO_ROOT);
        const fetch = [_][]const u8{ "git", "-C", pugixml_dir, "fetch", "--depth", "1", "origin", pugixml_revision };
        try common.runInherit(io, alloc, &fetch, REPO_ROOT);
        const checkout = [_][]const u8{ "git", "-C", pugixml_dir, "checkout", "--detach", "FETCH_HEAD" };
        try common.runInherit(io, alloc, &checkout, REPO_ROOT);
        if (!try allFilesExistUnder(io, alloc, pugixml_dir, &pugixml_required_files)) {
            return error.IncompleteExternalParser;
        }
    } else {
        const rev_argv = [_][]const u8{ "git", "-C", pugixml_dir, "rev-parse", "HEAD" };
        const rev_out = try common.runCaptureStdout(io, alloc, &rev_argv, REPO_ROOT);
        defer alloc.free(rev_out);
        const current_revision = std.mem.trim(u8, rev_out, " \t\r\n");
        if (!std.mem.eql(u8, current_revision, pugixml_revision)) {
            const fetch = [_][]const u8{ "git", "-C", pugixml_dir, "fetch", "--depth", "1", "origin", pugixml_revision };
            try common.runInherit(io, alloc, &fetch, REPO_ROOT);
            const checkout = [_][]const u8{ "git", "-C", pugixml_dir, "checkout", "--detach", "FETCH_HEAD" };
            try common.runInherit(io, alloc, &checkout, REPO_ROOT);
        }

        if (!try allFilesExistUnder(io, alloc, pugixml_dir, &pugixml_required_files)) {
            // bench/parsers is generated/ignored state. Repair deleted or partially
            // populated tracked files instead of treating the mere presence of
            // `.git` as a complete checkout.
            const repair = [_][]const u8{ "git", "-C", pugixml_dir, "reset", "--hard", "HEAD" };
            try common.runInherit(io, alloc, &repair, REPO_ROOT);
            if (!try allFilesExistUnder(io, alloc, pugixml_dir, &pugixml_required_files)) {
                return error.IncompleteExternalParser;
            }
        }
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
            common.runInherit(io, alloc, &unzip, REPO_ROOT) catch |err| switch (err) {
                error.FileNotFound => {
                    // Minimal Linux images may omit Info-ZIP while still shipping
                    // libarchive. Keep benchmark setup self-contained there.
                    const bsdtar = [_][]const u8{ "bsdtar", "-xf", zip_path, "-C", rapid_tmp };
                    try common.runInherit(io, alloc, &bsdtar, REPO_ROOT);
                },
                else => return err,
            };
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
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_tiny_empty.xml", "<x/>", 220_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_tiny_text.xml", "<x>a</x>", 120_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_one_attr.xml", "<x a='1'/>", 90_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_two_attr.xml", "<x a='1' b='2'/>", 65_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_attrs4.xml", "<x a='1' b='2' c='3' d='4'/>", 38_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_attrs8.xml", "<x a='1' b='2' c='3' d='4' e='5' f='6' g='7' h='8'/>", 21_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_single_quotes.xml", "<item a='1' b='two' c='three four'/>", 28_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_unicode_names.xml", "<élément α='1' 日本語='値'>текст</élément>", 22_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_pretty_indented.xml", "\n  <group>\n    <item a='1'>value</item>\n    <item a='2'>value</item>\n  </group>", 12_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_crlf_pretty.xml", "\r\n\t<item a='1'>\r\n\t\tvalue\r\n\t</item>", 24_000);
    try writeRepeatedSynthetic(io, FIXTURES_DIR ++ "/synthetic_token_whitespace_mix.xml", "<x\t a='1'\n b = '2'\r c\t=\t'3' />\n", 27_000);
    // Diagnostic-only shapes: generated for focused investigations, but kept
    // out of quick/stable profiles because they distort headline parser rates.
    try writeLongText(io, FIXTURES_DIR ++ "/synthetic_long_text.xml");
    try writeDoctypeEntities(io, FIXTURES_DIR ++ "/synthetic_doctype_entities.xml");
    try writeAttrCountMix(io, FIXTURES_DIR ++ "/synthetic_attr_count_mix.xml");
}

fn writeRepeatedSynthetic(io: std.Io, path: []const u8, row: []const u8, count: usize) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<root>");
    for (0..count) |_| try out.writeAll(row);
    try out.writeAll("</root>");
    try out.flush();
}

fn writeLongText(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<root>");
    const chunk = "abcdefghijklmnopqrstuvwxyz0123456789 ";
    for (0..28_000) |_| try out.writeAll(chunk);
    try out.writeAll("</root>");
    try out.flush();
}

fn writeDoctypeEntities(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<!DOCTYPE root [<!ENTITY a 'alpha'><!ENTITY b '&a; beta'><!ELEMENT root (#PCDATA)>]><root>");
    for (0..160_000) |_| try out.writeAll("&b; ");
    try out.writeAll("</root>");
    try out.flush();
}

fn writeAttrCountMix(io: std.Io, path: []const u8) !void {
    var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    var out_buf: [4096]u8 = undefined;
    var out_writer = file.writer(io, &out_buf);
    const out = &out_writer.interface;
    try out.writeAll("<root>");
    for (0..4_000) |_| {
        for (0..17) |count| {
            try out.writeAll("<x");
            for (0..count) |i| try out.print(" a{d}='{d}'", .{ i, i });
            try out.writeAll("/>");
        }
    }
    try out.writeAll("</root>");
    try out.flush();
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
        // These fixtures come from the pinned pugixml revision, so always
        // refresh them. Reusing an older cached copy after the pinned revision
        // changes makes the benchmark corpus silently non-reproducible.
        try copyFixtureIfPresent(io, alloc, item.src, item.out, true);
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

fn commandAvailable(io: std.Io, alloc: std.mem.Allocator, name: []const u8) bool {
    const argv = [_][]const u8{ name, "--version" };
    const out = common.runCaptureStdout(io, alloc, &argv, REPO_ROOT) catch return false;
    alloc.free(out);
    return true;
}

fn appendCxxPrefix(io: std.Io, alloc: std.mem.Allocator, argv: *std.ArrayList([]const u8)) !void {
    if (commandAvailable(io, alloc, "c++")) {
        try argv.append(alloc, "c++");
    } else {
        // Zig ships a Clang C++ driver, so the benchmark suite does not need a
        // separately installed system compiler on minimal hosts.
        try argv.appendSlice(alloc, &.{ "zig", "c++" });
    }
}

fn buildRunners(io: std.Io, alloc: std.mem.Allocator) !void {
    try common.ensureDir(io, BUILD_DIR);
    try common.ensureDir(io, BIN_DIR);
    try common.ensureDir(io, TMP_SCRATCH_DIR);

    // Match zhtml: build the installed benchmark binary directly. The tools
    // executable is already running, so bench-only avoids recursive tool builds.
    const zig_build = [_][]const u8{ "zig", "build", "bench-only", "-Doptimize=ReleaseFast", "-Dcpu=native" };
    try runInheritWithBenchTmp(io, alloc, &zig_build, REPO_ROOT);

    var pugixml_cc = std.ArrayList([]const u8).empty;
    defer pugixml_cc.deinit(alloc);
    try appendCxxPrefix(io, alloc, &pugixml_cc);
    try pugixml_cc.appendSlice(alloc, &.{
        "-O3",                              "-DNDEBUG",                              "-march=native",               "-std=c++17", "-Wall",                          "-Wextra", "-Werror",
        "bench/runners/pugixml_runner.cpp", "bench/parsers/pugixml/src/pugixml.cpp", "-Ibench/parsers/pugixml/src", "-o",         "bench/build/bin/pugixml_runner",
    });
    try runInheritWithBenchTmp(io, alloc, pugixml_cc.items, REPO_ROOT);

    var rapidxml_cc = std.ArrayList([]const u8).empty;
    defer rapidxml_cc.deinit(alloc);
    try appendCxxPrefix(io, alloc, &rapidxml_cc);
    try rapidxml_cc.appendSlice(alloc, &.{
        "-O3",                               "-DNDEBUG",                 "-march=native", "-std=c++17",                      "-Wall", "-Wextra", "-Werror",
        "bench/runners/rapidxml_runner.cpp", "-Ibench/parsers/rapidxml", "-o",            "bench/build/bin/rapidxml_runner",
    });
    try runInheritWithBenchTmp(io, alloc, rapidxml_cc.items, REPO_ROOT);
}

fn runParser(io: std.Io, alloc: std.mem.Allocator, parser_name: []const u8, fixture_path: []const u8, iterations: usize) !u64 {
    const iters = try std.fmt.allocPrint(alloc, "{d}", .{iterations});
    defer alloc.free(iters);

    var argv: [5][]const u8 = undefined;
    var argc: usize = 0;

    if (std.mem.eql(u8, parser_name, "ours-validated")) {
        argv = .{ "zig-out/bin/zxml-bench", "parse", "validated", fixture_path, iters };
        argc = 5;
    } else if (std.mem.eql(u8, parser_name, "ours-permissive")) {
        argv = .{ "zig-out/bin/zxml-bench", "parse", "permissive", fixture_path, iters };
        argc = 5;
    } else if (std.mem.eql(u8, parser_name, "stream-validated")) {
        argv = .{ "zig-out/bin/zxml-stream-bench", "parse", "validated", fixture_path, iters };
        argc = 5;
    } else if (std.mem.eql(u8, parser_name, "stream-permissive")) {
        argv = .{ "zig-out/bin/zxml-stream-bench", "parse", "permissive", fixture_path, iters };
        argc = 5;
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

    const out = try common.runCaptureStdout(io, alloc, argv[0..argc], REPO_ROOT);
    defer alloc.free(out);
    return common.parseExactU64(out);
}

fn finishParseBench(
    alloc: std.mem.Allocator,
    parser_name: []const u8,
    fixture: FixtureCase,
    fixture_size: u64,
    calibrated_iterations: usize,
    samples: []u64,
) !ParseResult {
    const median = try common.medianU64(alloc, samples);
    const bytes_total = @as(f64, @floatFromInt(fixture_size)) * @as(f64, @floatFromInt(calibrated_iterations));
    const throughput = if (median == 0) 0.0 else (bytes_total / 1_000_000.0) / (@as(f64, @floatFromInt(median)) / 1_000_000_000.0);

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

fn calibratedIterationCount(base_iterations: usize, base_ns: u64) usize {
    if (base_ns == 0 or (base_ns >= min_sample_ns and base_ns <= max_sample_ns)) return base_iterations;

    // Scale both directions toward a stable target. Historical iteration hints
    // were tuned for retained-capacity parsing; after methodology or parser
    // changes they can be wildly too large as well as too small.
    const numerator = @as(u128, base_iterations) * @as(u128, target_sample_ns);
    const scaled_u128 = (numerator + base_ns - 1) / base_ns;
    const max_iterations = @as(u128, base_iterations) * 10_000;
    return @intCast(@max(@as(u128, 1), @min(scaled_u128, max_iterations)));
}

fn calibrateIterations(io: std.Io, alloc: std.mem.Allocator, parser_name: []const u8, fixture_path: []const u8, base_iterations: usize) !usize {
    const base_ns = try runParser(io, alloc, parser_name, fixture_path, base_iterations);
    return calibratedIterationCount(base_iterations, base_ns);
}

test "benchmark iteration calibration scales up and down" {
    try std.testing.expectEqual(@as(usize, 100), calibratedIterationCount(100, 40_000_000));
    try std.testing.expectEqual(@as(usize, 400), calibratedIterationCount(100, 10_000_000));
    try std.testing.expectEqual(@as(usize, 20), calibratedIterationCount(100, 200_000_000));
    try std.testing.expectEqual(@as(usize, 1), calibratedIterationCount(1, 400_000_000));
    try std.testing.expectEqual(@as(usize, 100), calibratedIterationCount(100, 0));
}

fn fixtureResultsComplete(rows: []const ParseResult, parsers: []const []const u8, fx: FixtureCase) bool {
    for (parsers) |parser_name| {
        if (!parserAppliesToFixture(parser_name, fx)) continue;
        var found = false;
        for (rows) |row| {
            if (std.mem.eql(u8, row.parser, parser_name) and std.mem.eql(u8, row.fixture, fx.name)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn benchmarkEnvironmentMatchesResume(environment: BenchmarkEnvironment, state: BenchmarkResumeState) bool {
    return std.mem.eql(u8, environment.os, state.os) and
        std.mem.eql(u8, environment.architecture, state.architecture) and
        std.mem.eql(u8, environment.cpu_model, state.cpu_model) and
        std.mem.eql(u8, environment.zig_version, state.zig_version) and
        std.mem.eql(u8, environment.cxx_driver, state.cxx_driver);
}

fn writeStableResumeCheckpoint(
    io: std.Io,
    alloc: std.mem.Allocator,
    context: BenchmarkResumeContext,
    rows: []const ParseResult,
) !void {
    var out: std.Io.Writer.Allocating = .init(alloc);
    defer out.deinit();
    const w = &out.writer;
    const env = context.environment.*;
    try w.print(
        "{{\n  \"profile\":\"stable\",\n  \"methodology_version\":{d},\n  \"source_head\":\"{s}\",\n  \"os\":{f},\n  \"architecture\":{f},\n  \"cpu_model\":{f},\n  \"zig_version\":{f},\n  \"cxx_driver\":{f},\n  \"parse_results\":[\n",
        .{ benchmark_methodology_version, context.source_head, std.json.fmt(env.os, .{}), std.json.fmt(env.architecture, .{}), std.json.fmt(env.cpu_model, .{}), std.json.fmt(env.zig_version, .{}), std.json.fmt(env.cxx_driver, .{}) },
    );
    for (rows, 0..) |row, row_index| {
        try w.print(
            "    {{\"parser\":{f},\"fixture\":{f},\"is_real\":{s},\"iterations\":{d},\"samples_ns\":[",
            .{ std.json.fmt(row.parser, .{}), std.json.fmt(row.fixture, .{}), if (row.is_real) "true" else "false", row.iterations },
        );
        for (row.samples_ns, 0..) |sample, sample_index| {
            if (sample_index != 0) try w.writeByte(',');
            try w.print("{d}", .{sample});
        }
        try w.print(
            "],\"median_ns\":{d},\"throughput_mb_s\":{d:.9}}}{s}\n",
            .{ row.median_ns, row.throughput_mb_s, if (row_index + 1 == rows.len) "" else "," },
        );
    }
    try w.writeAll("  ]\n}\n");
    const checkpoint = try out.toOwnedSlice();
    defer alloc.free(checkpoint);
    try common.writeFile(io, STABLE_RESUME_PATH, checkpoint);
}

fn loadStableResumeCheckpoint(
    io: std.Io,
    alloc: std.mem.Allocator,
    source_head: []const u8,
    environment: BenchmarkEnvironment,
    results: *std.ArrayList(ParseResult),
) !void {
    if (!common.fileExists(io, STABLE_RESUME_PATH)) return;
    const raw = try common.readFileAlloc(io, alloc, STABLE_RESUME_PATH);
    defer alloc.free(raw);
    var parsed = std.json.parseFromSlice(BenchmarkResumeState, alloc, raw, .{}) catch {
        std.debug.print("ignoring unreadable stable resume checkpoint\n", .{});
        return;
    };
    defer parsed.deinit();
    const state = parsed.value;
    if (!std.mem.eql(u8, state.profile, "stable") or
        state.methodology_version != benchmark_methodology_version or
        !std.mem.eql(u8, state.source_head, source_head) or
        !benchmarkEnvironmentMatchesResume(environment, state))
    {
        std.debug.print("ignoring stale stable resume checkpoint\n", .{});
        return;
    }

    for (state.parse_results) |row| {
        const parser = try alloc.dupe(u8, row.parser);
        errdefer alloc.free(parser);
        const fixture = try alloc.dupe(u8, row.fixture);
        errdefer alloc.free(fixture);
        const samples = try alloc.dupe(u64, row.samples_ns);
        errdefer alloc.free(samples);
        try results.append(alloc, .{
            .parser = parser,
            .fixture = fixture,
            .is_real = row.is_real,
            .iterations = row.iterations,
            .samples_ns = samples,
            .median_ns = row.median_ns,
            .throughput_mb_s = row.throughput_mb_s,
        });
    }
    std.debug.print("resumed {d} stable benchmark result row(s)\n", .{state.parse_results.len});
}

fn benchmarkFixtureSet(
    io: std.Io,
    alloc: std.mem.Allocator,
    fixtures: []const FixtureCase,
    parsers: []const []const u8,
    results: *std.ArrayList(ParseResult),
    resume_context: ?BenchmarkResumeContext,
) !void {
    for (fixtures, 0..) |fx, fixture_index| {
        if (resume_context != null and fixtureResultsComplete(results.items, parsers, fx)) {
            std.debug.print("resume skip: fixture={s}\n", .{fx.name});
            continue;
        }
        const fixture_path = try std.fmt.allocPrint(alloc, FIXTURES_DIR ++ "/{s}", .{fx.name});
        defer alloc.free(fixture_path);
        const fixture_stat = try std.Io.Dir.cwd().statFile(io, fixture_path, .{});

        const calibrated = try alloc.alloc(usize, parsers.len);
        defer alloc.free(calibrated);
        const sample_sets = try alloc.alloc(?[]u64, parsers.len);
        defer alloc.free(sample_sets);
        @memset(sample_sets, null);
        errdefer for (sample_sets) |samples| {
            if (samples) |owned| alloc.free(owned);
        };

        // Rotate calibration order so setup work does not always heat the same
        // parser immediately before measurement.
        for (0..parsers.len) |offset| {
            const parser_index = (fixture_index + offset) % parsers.len;
            const parser_name = parsers[parser_index];
            if (!parserAppliesToFixture(parser_name, fx)) continue;
            calibrated[parser_index] = try calibrateIterations(io, alloc, parser_name, fixture_path, fx.iterations);
            sample_sets[parser_index] = try alloc.alloc(u64, repeats);
        }

        // Interleave parser samples and rotate who runs first on every repeat.
        for (0..repeats) |rep| {
            for (0..parsers.len) |offset| {
                const parser_index = (fixture_index + rep + offset) % parsers.len;
                const parser_name = parsers[parser_index];
                if (!parserAppliesToFixture(parser_name, fx)) continue;
                std.debug.print(
                    "running parse: parser={s} fixture={s} iterations={d} sample={d}/{d}\n",
                    .{ parser_name, fx.name, calibrated[parser_index], rep + 1, repeats },
                );
                sample_sets[parser_index].?[rep] = try runParser(io, alloc, parser_name, fixture_path, calibrated[parser_index]);
            }
        }

        for (parsers, 0..) |parser_name, parser_index| {
            const samples = sample_sets[parser_index] orelse continue;
            sample_sets[parser_index] = null;
            var result = finishParseBench(alloc, parser_name, fx, fixture_stat.size, calibrated[parser_index], samples) catch |err| {
                alloc.free(samples);
                return err;
            };
            errdefer freeParseResult(alloc, &result);
            try results.append(alloc, result);
        }
        if (resume_context) |context| try writeStableResumeCheckpoint(io, alloc, context, results.items);
    }
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

fn evaluateValidatedRegressionChecks(
    alloc: std.mem.Allocator,
    main_results: []const ParseResult,
    regression_results: []const ParseResult,
) ![]ValidatedRegressionCheck {
    var out = std.ArrayList(ValidatedRegressionCheck).empty;
    errdefer out.deinit(alloc);

    for (validated_regression_parsers) |parser_name| {
        for (validated_regression_fixtures) |fixture| {
            const throughput = findThroughput(regression_results, parser_name, fixture.name) orelse return error.MissingBenchmarkResult;
            const reference = findThroughput(main_results, parser_name, validated_regression_reference_fixture) orelse return error.MissingBenchmarkResult;
            const ratio = if (reference == 0.0) 0.0 else throughput / reference;
            try out.append(alloc, .{
                .parser = parser_name,
                .fixture = fixture.name,
                .reference_fixture = validated_regression_reference_fixture,
                .throughput_mb_s = throughput,
                .reference_mb_s = reference,
                .reference_ratio = ratio,
                .pass = ratio >= validated_regression_min_reference_ratio,
            });
        }
    }

    return out.toOwnedSlice(alloc);
}

fn validatedRegressionPassCount(checks: []const ValidatedRegressionCheck) usize {
    var count: usize = 0;
    for (checks) |check| count += @intFromBool(check.pass);
    return count;
}

fn validatedRegressionsAllPass(checks: []const ValidatedRegressionCheck) bool {
    return validatedRegressionPassCount(checks) == checks.len;
}

fn parserAppliesToFixture(parser_name: []const u8, fixture: FixtureCase) bool {
    if (fixture.validated_valid) return true;
    return !std.mem.eql(u8, parser_name, "ours-validated") and !std.mem.eql(u8, parser_name, "stream-validated");
}

fn evaluateGateRows(alloc: std.mem.Allocator, profile: Profile, rows: []const ParseResult) ![]GateRow {
    var out = std.ArrayList(GateRow).empty;
    errdefer {
        for (out.items) |r| alloc.free(r.fixture);
        out.deinit(alloc);
    }

    for (profile.fixtures) |fx| {
        const ours = findThroughput(rows, "ours-permissive", fx.name) orelse return error.MissingBenchmarkResult;
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
            .ours_permissive_mb_s = ours,
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

fn evaluateStreamComparisonRows(alloc: std.mem.Allocator, profile: Profile, rows: []const ParseResult) ![]StreamComparisonRow {
    var out = std.ArrayList(StreamComparisonRow).empty;
    errdefer {
        for (out.items) |r| alloc.free(r.fixture);
        out.deinit(alloc);
    }

    for (profile.fixtures) |fx| {
        if (!fx.validated_valid) continue;
        const dom_permissive = findThroughput(rows, "ours-permissive", fx.name) orelse return error.MissingBenchmarkResult;
        const stream_permissive = findThroughput(rows, "stream-permissive", fx.name) orelse return error.MissingBenchmarkResult;
        const dom_validated = findThroughput(rows, "ours-validated", fx.name) orelse return error.MissingBenchmarkResult;
        const stream_validated = findThroughput(rows, "stream-validated", fx.name) orelse return error.MissingBenchmarkResult;

        const permissive_ratio = if (dom_permissive == 0) 0 else stream_permissive / dom_permissive;
        const validated_ratio = if (dom_validated == 0) 0 else stream_validated / dom_validated;
        const fixture = try alloc.dupe(u8, fx.name);
        errdefer alloc.free(fixture);
        try out.append(alloc, .{
            .fixture = fixture,
            .is_real = fx.is_real,
            .dom_permissive_mb_s = dom_permissive,
            .stream_permissive_mb_s = stream_permissive,
            .permissive_ratio = permissive_ratio,
            .dom_validated_mb_s = dom_validated,
            .stream_validated_mb_s = stream_validated,
            .validated_ratio = validated_ratio,
        });
    }

    return out.toOwnedSlice(alloc);
}

fn freeStreamComparisonRows(alloc: std.mem.Allocator, rows: []StreamComparisonRow) void {
    for (rows) |r| alloc.free(r.fixture);
    alloc.free(rows);
}

const AverageThroughputRow = struct {
    parser: []const u8,
    avg_mb_s: f64,
};

fn makeAverageThroughputRows(alloc: std.mem.Allocator, parse_results: []const ParseResult) ![]AverageThroughputRow {
    const parser_names = [_][]const u8{ "ours-permissive", "ours-validated", "stream-permissive", "stream-validated", "pugixml", "rapidxml" };
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
        .{ .parser = "ours-permissive", .fixture = "x.xml", .is_real = true, .iterations = 1, .samples_ns = &sample_a, .median_ns = 1, .throughput_mb_s = 120.0 },
        .{ .parser = "pugixml", .fixture = "x.xml", .is_real = true, .iterations = 1, .samples_ns = &sample_b, .median_ns = 1, .throughput_mb_s = 110.0 },
        .{ .parser = "rapidxml", .fixture = "x.xml", .is_real = true, .iterations = 1, .samples_ns = &sample_c, .median_ns = 1, .throughput_mb_s = 100.0 },
    };

    const gates = try evaluateGateRows(alloc, profile, &rows);
    defer freeGateRows(alloc, gates);

    try std.testing.expectEqual(@as(usize, 1), gates.len);
    try std.testing.expectEqualStrings("pugixml", gates[0].best_external_parser);
    try std.testing.expect(gates[0].pass);
}

fn lscpuField(entries: []const LscpuEntry, name: []const u8) ?[]const u8 {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.field, name)) return entry.data;
    }
    return null;
}

test "benchmark environment field lookup matches lscpu labels" {
    const entries = [_]LscpuEntry{
        .{ .field = "Architecture:", .data = "x86_64" },
        .{ .field = "Model name:", .data = "Example CPU" },
    };
    try std.testing.expectEqualStrings("x86_64", lscpuField(&entries, "Architecture:").?);
    try std.testing.expectEqualStrings("Example CPU", lscpuField(&entries, "Model name:").?);
    try std.testing.expect(lscpuField(&entries, "CPU max MHz:") == null);
}

fn dupeEnvironmentValue(alloc: std.mem.Allocator, value: ?[]const u8) ![]const u8 {
    return alloc.dupe(u8, value orelse "unavailable");
}

fn collectBenchmarkEnvironment(io: std.Io, alloc: std.mem.Allocator) !BenchmarkEnvironment {
    const uname = common.runCaptureStdout(io, alloc, &.{ "uname", "-sr" }, REPO_ROOT) catch null;
    defer if (uname) |value| alloc.free(value);
    const lscpu_json = common.runCaptureStdout(io, alloc, &.{ "lscpu", "--json" }, REPO_ROOT) catch null;
    defer if (lscpu_json) |value| alloc.free(value);
    const zig_version_out = common.runCaptureStdout(io, alloc, &.{ "zig", "version" }, REPO_ROOT) catch null;
    defer if (zig_version_out) |value| alloc.free(value);

    var parsed: ?std.json.Parsed(LscpuOutput) = null;
    if (lscpu_json) |json| parsed = std.json.parseFromSlice(LscpuOutput, alloc, json, .{}) catch null;
    defer if (parsed) |value| value.deinit();

    const entries = if (parsed) |value| value.value.lscpu else &[_]LscpuEntry{};
    const os = try dupeEnvironmentValue(alloc, uname);
    errdefer alloc.free(os);
    const architecture = try dupeEnvironmentValue(alloc, lscpuField(entries, "Architecture:"));
    errdefer alloc.free(architecture);
    const cpu_model = try dupeEnvironmentValue(alloc, lscpuField(entries, "Model name:"));
    errdefer alloc.free(cpu_model);
    const cpu_scaling = try dupeEnvironmentValue(alloc, lscpuField(entries, "CPU(s) scaling MHz:"));
    errdefer alloc.free(cpu_scaling);
    const cpu_min_mhz = try dupeEnvironmentValue(alloc, lscpuField(entries, "CPU min MHz:"));
    errdefer alloc.free(cpu_min_mhz);
    const cpu_max_mhz = try dupeEnvironmentValue(alloc, lscpuField(entries, "CPU max MHz:"));
    errdefer alloc.free(cpu_max_mhz);
    const zig_version = try dupeEnvironmentValue(alloc, zig_version_out);
    errdefer alloc.free(zig_version);
    const cxx_driver = try alloc.dupe(u8, if (commandAvailable(io, alloc, "c++")) "c++" else "zig c++");
    errdefer alloc.free(cxx_driver);
    return .{
        .os = os,
        .architecture = architecture,
        .cpu_model = cpu_model,
        .cpu_scaling = cpu_scaling,
        .cpu_min_mhz = cpu_min_mhz,
        .cpu_max_mhz = cpu_max_mhz,
        .zig_version = zig_version,
        .cxx_driver = cxx_driver,
    };
}

fn writeReadmeBenchmarkEnvironment(w: anytype, environment: BenchmarkEnvironment) !void {
    try w.print("Tested on `{s}` with CPU `{s}` using Zig `{s}`.\n\n", .{ environment.os, environment.cpu_model, environment.zig_version });
}

fn writeBenchmarkEnvironmentTable(w: anytype, heading: []const u8, environment: BenchmarkEnvironment) !void {
    try w.print("{s} Benchmark Environment\n\n", .{heading});
    try w.writeAll("| Property | Value |\n|---|---|\n");
    try w.print("| OS / kernel | {s} |\n", .{environment.os});
    try w.print("| Architecture | {s} |\n", .{environment.architecture});
    try w.print("| CPU | {s} |\n", .{environment.cpu_model});
    try w.print("| CPU frequency scaling | {s} |\n", .{environment.cpu_scaling});
    try w.print("| CPU MHz range | {s}–{s} |\n", .{ environment.cpu_min_mhz, environment.cpu_max_mhz });
    try w.print("| Zig | {s} (`ReleaseFast -Dcpu=native`) |\n", .{environment.zig_version});
    try w.print("| C++ driver | {s} (`-O3 -DNDEBUG -march=native`) |\n\n", .{environment.cxx_driver});
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
    environment: BenchmarkEnvironment,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_comparison_rows: []const StreamComparisonRow,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    const averages = try makeAverageThroughputRows(alloc, parse_results);
    defer alloc.free(averages);

    try w.print("Source: `bench/results/latest.json` (`{s}` profile).\n\n", .{profile_name});
    try writeReadmeBenchmarkEnvironment(w, environment);
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
    try w.print("| `{s}` | {d}/{d} | `ours-permissive >= max(pugixml, rapidxml)` |\n", .{
        profile_name,
        pass_count,
        gate_rows.len,
    });
    _ = stream_comparison_rows;

    return out.toOwnedSlice();
}

fn renderBenchReadmeSnapshot(
    alloc: std.mem.Allocator,
    environment: BenchmarkEnvironment,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_comparison_rows: []const StreamComparisonRow,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("Source: `bench/results/latest.json` (`{s}` profile).\n\n", .{profile_name});
    try w.writeAll("## Latest Benchmark Snapshot\n\n");
    try writeBenchmarkEnvironmentTable(w, "###", environment);
    try w.writeAll("### Parse Throughput Comparison (MB/s)\n\n");
    try w.writeAll("| Fixture | ours-permissive | ours-validated | stream-permissive | stream-validated | pugixml | rapidxml |\n");
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
        if (findParseResult(parse_results, "ours-permissive", fixture_name)) |r| {
            try w.print("{d:.2}", .{r.throughput_mb_s});
        } else try w.writeAll("-");
        try w.writeAll(" | ");
        if (findParseResult(parse_results, "ours-validated", fixture_name)) |r| {
            try w.print("{d:.2}", .{r.throughput_mb_s});
        } else try w.writeAll("-");
        try w.writeAll(" | ");
        if (findParseResult(parse_results, "stream-permissive", fixture_name)) |r| {
            try w.print("{d:.2}", .{r.throughput_mb_s});
        } else try w.writeAll("-");
        try w.writeAll(" | ");
        if (findParseResult(parse_results, "stream-validated", fixture_name)) |r| {
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
    try w.writeAll("| Fixture | ours-permissive | best external | ours/best-ext | Result |\n");
    try w.writeAll("|---|---:|---|---:|---|\n");
    for (gate_rows) |g| {
        try w.print(
            "| `{s}` | {d:.2} | `{s}` {d:.2} | {d:.3} | {s} |\n",
            .{
                g.fixture,
                g.ours_permissive_mb_s,
                g.best_external_parser,
                g.best_external_mb_s,
                g.external_ratio,
                if (g.pass) "PASS" else "FAIL",
            },
        );
    }

    if (stream_comparison_rows.len != 0) {
        try w.writeAll("\n### Streaming Comparison (Advisory)\n\n");
        try w.writeAll("| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |\n");
        try w.writeAll("|---|---:|---:|---:|---:|---:|---:|\n");
        for (stream_comparison_rows) |g| {
            try w.print(
                "| `{s}` | {d:.2} | {d:.2} | {d:.3} | {d:.2} | {d:.2} | {d:.3} |\n",
                .{
                    g.fixture,
                    g.stream_permissive_mb_s,
                    g.dom_permissive_mb_s,
                    g.permissive_ratio,
                    g.stream_validated_mb_s,
                    g.dom_validated_mb_s,
                    g.validated_ratio,
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
    environment: BenchmarkEnvironment,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_comparison_rows: []const StreamComparisonRow,
) !void {
    const root_summary = try renderReadmeAutoSummary(alloc, environment, profile_name, parse_results, gate_rows, stream_comparison_rows);
    defer alloc.free(root_summary);
    try updateFileSection(io, alloc, "README.md", ReadmeSummaryStartMarker, ReadmeSummaryEndMarker, root_summary);

    const bench_snapshot = try renderBenchReadmeSnapshot(alloc, environment, profile_name, parse_results, gate_rows, stream_comparison_rows);
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
    environment: BenchmarkEnvironment,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_comparison_rows: []const StreamComparisonRow,
    validated_regression_checks: []const ValidatedRegressionCheck,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print("# ZXML Benchmark Results\n\nGenerated (unix): {d}\n\nProfile: `{s}`\n\n", .{ common.nowUnix(io), profile_name });
    try writeBenchmarkEnvironmentTable(w, "##", environment);

    try w.writeAll("## Parse Throughput\n\n");
    try w.writeAll("| Fixture | Parser | Throughput (MB/s) | Median Time (ms) | Iterations |\n");
    try w.writeAll("|---|---|---:|---:|---:|\n");
    for (parse_results) |r| {
        const median_ms = @as(f64, @floatFromInt(r.median_ns)) / 1_000_000.0;
        try w.print("| {s} | {s} | {d:.2} | {d:.2} | {d} |\n", .{ r.fixture, r.parser, r.throughput_mb_s, median_ms, r.iterations });
    }

    if (gate_rows.len != 0) {
        try w.writeAll("\n## Stable Gates\n\n");
        try w.writeAll("| Fixture | ours-permissive | pugixml | rapidxml | best external | ours/best-ext | Result |\n");
        try w.writeAll("|---|---:|---:|---:|---|---:|---|\n");
        for (gate_rows) |g| {
            try w.print(
                "| {s} | {d:.2} | {d:.2} | {d:.2} | {s} {d:.2} | {d:.3} | {s} |\n",
                .{
                    g.fixture,
                    g.ours_permissive_mb_s,
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

    if (stream_comparison_rows.len != 0) {
        try w.writeAll("\n## Streaming Comparison (Advisory)\n\n");
        try w.writeAll("| Fixture | stream-permissive | ours-permissive | stream/ours | stream-validated | ours-validated | stream/ours |\n");
        try w.writeAll("|---|---:|---:|---:|---:|---:|---:|\n");
        for (stream_comparison_rows) |g| {
            try w.print(
                "| {s} | {d:.2} | {d:.2} | {d:.3} | {d:.2} | {d:.2} | {d:.3} |\n",
                .{
                    g.fixture,
                    g.stream_permissive_mb_s,
                    g.dom_permissive_mb_s,
                    g.permissive_ratio,
                    g.stream_validated_mb_s,
                    g.dom_validated_mb_s,
                    g.validated_ratio,
                },
            );
        }
    }

    if (validated_regression_checks.len != 0) {
        const passed = validatedRegressionPassCount(validated_regression_checks);
        try w.print("\n## Validated Pathology Regression Checks\n\n{d}/{d} passed. These fixtures are excluded from headline averages and stable external gates.\n", .{ passed, validated_regression_checks.len });
        if (!validatedRegressionsAllPass(validated_regression_checks)) {
            try w.writeAll("\n| Parser | Fixture | Throughput (MB/s) | Reference | Reference MB/s | Ratio | Result |\n");
            try w.writeAll("|---|---|---:|---|---:|---:|---|\n");
            for (validated_regression_checks) |check| {
                try w.print("| {s} | {s} | {d:.2} | {s} | {d:.2} | {d:.3} | {s} |\n", .{
                    check.parser,
                    check.fixture,
                    check.throughput_mb_s,
                    check.reference_fixture,
                    check.reference_mb_s,
                    check.reference_ratio,
                    if (check.pass) "PASS" else "FAIL",
                });
            }
        } else {
            try w.writeAll("Detailed timings remain in `bench/results/latest.json` for regression analysis.\n");
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
    stream_comparison_rows: []const StreamComparisonRow,
    validated_regression_checks: []const ValidatedRegressionCheck,
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
            "ours-permissive",
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
            const ours = try std.fmt.bufPrint(&ours_buf, "{d:.2}", .{g.ours_permissive_mb_s});
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
            const ours = try std.fmt.bufPrint(&ours_buf, "{d:.2}", .{g.ours_permissive_mb_s});

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

    if (stream_comparison_rows.len != 0) {
        try w.writeAll("\nStreaming Comparison (advisory)\n");
        const headers = [_][]const u8{
            "Fixture",
            "stream-permissive",
            "ours-permissive",
            "stream/ours",
            "stream-validated",
            "ours-validated",
            "stream/ours",
        };
        const header_align = [_]bool{ false, false, false, false, false, false, false };
        const row_align = [_]bool{ false, true, true, true, true, true, true };
        var widths = [_]usize{
            headers[0].len,
            headers[1].len,
            headers[2].len,
            headers[3].len,
            headers[4].len,
            headers[5].len,
            headers[6].len,
        };

        for (stream_comparison_rows) |g| {
            widths[0] = maxUsize(widths[0], g.fixture.len);
            inline for (&.{ g.stream_permissive_mb_s, g.dom_permissive_mb_s, g.permissive_ratio, g.stream_validated_mb_s, g.dom_validated_mb_s, g.validated_ratio }, 1..) |value, col| {
                var buf: [32]u8 = undefined;
                const txt = if (col == 3 or col == 6)
                    try std.fmt.bufPrint(&buf, "{d:.3}", .{value})
                else
                    try std.fmt.bufPrint(&buf, "{d:.2}", .{value});
                widths[col] = maxUsize(widths[col], txt.len);
            }
        }

        try writeTableBorder(w, &widths);
        try writeTableRow(w, &headers, &widths, &header_align);
        try writeTableBorder(w, &widths);
        for (stream_comparison_rows) |g| {
            var stream_permissive_buf: [32]u8 = undefined;
            const stream_permissive = try std.fmt.bufPrint(&stream_permissive_buf, "{d:.2}", .{g.stream_permissive_mb_s});
            var dom_permissive_buf: [32]u8 = undefined;
            const dom_permissive = try std.fmt.bufPrint(&dom_permissive_buf, "{d:.2}", .{g.dom_permissive_mb_s});
            var permissive_ratio_buf: [32]u8 = undefined;
            const permissive_ratio = try std.fmt.bufPrint(&permissive_ratio_buf, "{d:.3}", .{g.permissive_ratio});
            var stream_validated_buf: [32]u8 = undefined;
            const stream_validated = try std.fmt.bufPrint(&stream_validated_buf, "{d:.2}", .{g.stream_validated_mb_s});
            var dom_validated_buf: [32]u8 = undefined;
            const dom_validated = try std.fmt.bufPrint(&dom_validated_buf, "{d:.2}", .{g.dom_validated_mb_s});
            var validated_ratio_buf: [32]u8 = undefined;
            const validated_ratio = try std.fmt.bufPrint(&validated_ratio_buf, "{d:.3}", .{g.validated_ratio});
            const row = [_][]const u8{
                g.fixture,
                stream_permissive,
                dom_permissive,
                permissive_ratio,
                stream_validated,
                dom_validated,
                validated_ratio,
            };
            try writeTableRow(w, &row, &widths, &row_align);
        }
        try writeTableBorder(w, &widths);
    }

    if (validated_regression_checks.len != 0) {
        const passed = validatedRegressionPassCount(validated_regression_checks);
        try w.print("\nValidated Pathology Regression Checks: {d}/{d} passed\n", .{ passed, validated_regression_checks.len });
        if (!validatedRegressionsAllPass(validated_regression_checks)) {
            const headers = [_][]const u8{ "Parser", "Fixture", "MB/s", "Reference", "Ref MB/s", "Ratio", "Result" };
            const row_align = [_]bool{ false, false, true, false, true, true, false };
            var widths = [_]usize{ headers[0].len, headers[1].len, headers[2].len, headers[3].len, headers[4].len, headers[5].len, headers[6].len };
            for (validated_regression_checks) |check| {
                widths[0] = maxUsize(widths[0], check.parser.len);
                widths[1] = maxUsize(widths[1], check.fixture.len);
                widths[3] = maxUsize(widths[3], check.reference_fixture.len);
                var a: [32]u8 = undefined;
                var b: [32]u8 = undefined;
                var c: [32]u8 = undefined;
                widths[2] = maxUsize(widths[2], (try std.fmt.bufPrint(&a, "{d:.2}", .{check.throughput_mb_s})).len);
                widths[4] = maxUsize(widths[4], (try std.fmt.bufPrint(&b, "{d:.2}", .{check.reference_mb_s})).len);
                widths[5] = maxUsize(widths[5], (try std.fmt.bufPrint(&c, "{d:.3}", .{check.reference_ratio})).len);
            }
            try writeTableBorder(w, &widths);
            try writeTableRow(w, &headers, &widths, &row_align);
            try writeTableBorder(w, &widths);
            for (validated_regression_checks) |check| {
                var a: [32]u8 = undefined;
                var b: [32]u8 = undefined;
                var c: [32]u8 = undefined;
                const row = [_][]const u8{
                    check.parser,
                    check.fixture,
                    try std.fmt.bufPrint(&a, "{d:.2}", .{check.throughput_mb_s}),
                    check.reference_fixture,
                    try std.fmt.bufPrint(&b, "{d:.2}", .{check.reference_mb_s}),
                    try std.fmt.bufPrint(&c, "{d:.3}", .{check.reference_ratio}),
                    if (check.pass) "PASS" else "FAIL",
                };
                try writeTableRow(w, &row, &widths, &row_align);
            }
            try writeTableBorder(w, &widths);
        } else {
            try w.writeAll("Pathological validated timings are hidden from the headline report; raw samples remain in latest.json.\n");
        }
    }

    return out.toOwnedSlice();
}

fn writeJson(
    io: std.Io,
    alloc: std.mem.Allocator,
    environment: BenchmarkEnvironment,
    profile_name: []const u8,
    parse_results: []const ParseResult,
    gate_rows: []const GateRow,
    stream_comparison_rows: []const StreamComparisonRow,
    validated_regression_results: []const ParseResult,
    validated_regression_checks: []const ValidatedRegressionCheck,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(alloc);
    errdefer out.deinit();
    const w = &out.writer;

    try w.print(
        "{{\n  \"generated_unix\": {d},\n  \"profile\": \"{s}\",\n  \"methodology_version\": {d},\n  \"environment\": {f},\n  \"parse_results\": [\n",
        .{ common.nowUnix(io), profile_name, benchmark_methodology_version, std.json.fmt(environment, .{}) },
    );
    for (parse_results, 0..) |r, i| {
        try w.print(
            "    {{\"parser\":\"{s}\",\"fixture\":\"{s}\",\"is_real\":{s},\"iterations\":{d},\"median_ns\":{d},\"throughput_mb_s\":{d:.6},\"samples_ns\":[",
            .{ r.parser, r.fixture, if (r.is_real) "true" else "false", r.iterations, r.median_ns, r.throughput_mb_s },
        );
        for (r.samples_ns, 0..) |sample, sample_index| {
            if (sample_index != 0) try w.writeByte(',');
            try w.print("{d}", .{sample});
        }
        try w.print("]}}{s}\n", .{if (i + 1 == parse_results.len) "" else ","});
    }
    try w.writeAll("  ],\n  \"gates\": [\n");
    for (gate_rows, 0..) |g, i| {
        try w.print(
            "    {{\"fixture\":\"{s}\",\"is_real\":{s},\"ours_permissive_mb_s\":{d:.6},\"pugixml_mb_s\":{d:.6},\"rapidxml_mb_s\":{d:.6},\"best_external_parser\":\"{s}\",\"best_external_mb_s\":{d:.6},\"external_ratio\":{d:.6},\"pass\":{s}}}{s}\n",
            .{
                g.fixture,
                if (g.is_real) "true" else "false",
                g.ours_permissive_mb_s,
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
    try w.writeAll("  ],\n  \"stream_comparisons\": [\n");
    for (stream_comparison_rows, 0..) |g, i| {
        try w.print(
            "    {{\"fixture\":\"{s}\",\"is_real\":{s},\"dom_permissive_mb_s\":{d:.6},\"stream_permissive_mb_s\":{d:.6},\"permissive_ratio\":{d:.6},\"dom_validated_mb_s\":{d:.6},\"stream_validated_mb_s\":{d:.6},\"validated_ratio\":{d:.6}}}{s}\n",
            .{
                g.fixture,
                if (g.is_real) "true" else "false",
                g.dom_permissive_mb_s,
                g.stream_permissive_mb_s,
                g.permissive_ratio,
                g.dom_validated_mb_s,
                g.stream_validated_mb_s,
                g.validated_ratio,
                if (i + 1 == stream_comparison_rows.len) "" else ",",
            },
        );
    }
    try w.writeAll("  ],\n  \"validated_regression_results\": [\n");
    for (validated_regression_results, 0..) |r, i| {
        try w.print(
            "    {{\"parser\":\"{s}\",\"fixture\":\"{s}\",\"is_real\":{s},\"iterations\":{d},\"median_ns\":{d},\"throughput_mb_s\":{d:.6},\"samples_ns\":[",
            .{ r.parser, r.fixture, if (r.is_real) "true" else "false", r.iterations, r.median_ns, r.throughput_mb_s },
        );
        for (r.samples_ns, 0..) |sample, sample_index| {
            if (sample_index != 0) try w.writeByte(',');
            try w.print("{d}", .{sample});
        }
        try w.print("]}}{s}\n", .{if (i + 1 == validated_regression_results.len) "" else ","});
    }
    try w.writeAll("  ],\n  \"validated_regression_checks\": [\n");
    for (validated_regression_checks, 0..) |check, i| {
        try w.print(
            "    {{\"parser\":\"{s}\",\"fixture\":\"{s}\",\"reference_fixture\":\"{s}\",\"throughput_mb_s\":{d:.6},\"reference_mb_s\":{d:.6},\"reference_ratio\":{d:.6},\"minimum_ratio\":{d:.6},\"pass\":{s}}}{s}\n",
            .{
                check.parser,
                check.fixture,
                check.reference_fixture,
                check.throughput_mb_s,
                check.reference_mb_s,
                check.reference_ratio,
                validated_regression_min_reference_ratio,
                if (check.pass) "true" else "false",
                if (i + 1 == validated_regression_checks.len) "" else ",",
            },
        );
    }
    try w.writeAll("  ]\n}\n");

    return out.toOwnedSlice();
}

fn runBenchmarks(io: std.Io, alloc: std.mem.Allocator, args: []const []const u8) !void {
    var profile_name: []const u8 = "quick";
    var write_baseline = false;
    var resume_stable = false;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--profile")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            profile_name = args[i];
        } else if (std.mem.eql(u8, arg, "--write-baseline")) {
            write_baseline = true;
        } else if (std.mem.eql(u8, arg, "--resume")) {
            resume_stable = true;
        } else {
            return error.InvalidArguments;
        }
    }

    const profile = try getProfile(profile_name);
    if (resume_stable and !std.mem.eql(u8, profile.name, "stable")) return error.InvalidArguments;
    const environment = try collectBenchmarkEnvironment(io, alloc);
    defer environment.deinit(alloc);

    try common.ensureDir(io, RESULTS_DIR);
    try ensureExternalParsersBuilt(io, alloc);
    try buildRunners(io, alloc);

    var parse_results = std.ArrayList(ParseResult).empty;
    defer {
        for (parse_results.items) |*r| freeParseResult(alloc, r);
        parse_results.deinit(alloc);
    }
    var source_head: ?[]u8 = null;
    defer if (source_head) |head| alloc.free(head);
    var resume_context: ?BenchmarkResumeContext = null;
    if (resume_stable) {
        source_head = try common.runCaptureStdout(io, alloc, &.{ "git", "rev-parse", "HEAD" }, REPO_ROOT);
        try loadStableResumeCheckpoint(io, alloc, source_head.?, environment, &parse_results);
        resume_context = .{ .source_head = source_head.?, .environment = &environment };
    }
    try benchmarkFixtureSet(io, alloc, profile.fixtures, &parse_parsers, &parse_results, resume_context);

    var validated_regression_results = std.ArrayList(ParseResult).empty;
    defer {
        for (validated_regression_results.items) |*r| freeParseResult(alloc, r);
        validated_regression_results.deinit(alloc);
    }
    var validated_regression_checks: []ValidatedRegressionCheck = try alloc.alloc(ValidatedRegressionCheck, 0);
    defer alloc.free(validated_regression_checks);
    if (std.mem.eql(u8, profile.name, "stable")) {
        try benchmarkFixtureSet(io, alloc, &validated_regression_fixtures, &validated_regression_parsers, &validated_regression_results, null);
        alloc.free(validated_regression_checks);
        validated_regression_checks = try evaluateValidatedRegressionChecks(alloc, parse_results.items, validated_regression_results.items);
    }

    const gate_rows = try evaluateGateRows(alloc, profile, parse_results.items);
    defer freeGateRows(alloc, gate_rows);
    const stream_comparison_rows = try evaluateStreamComparisonRows(alloc, profile, parse_results.items);
    defer freeStreamComparisonRows(alloc, stream_comparison_rows);

    const md = try writeMarkdown(io, alloc, environment, profile.name, parse_results.items, gate_rows, stream_comparison_rows, validated_regression_checks);
    defer alloc.free(md);
    try common.writeFile(io, RESULTS_DIR ++ "/latest.md", md);

    const terminal = try writeTerminalReport(io, alloc, profile.name, parse_results.items, gate_rows, stream_comparison_rows, validated_regression_checks);
    defer alloc.free(terminal);

    const json = try writeJson(
        io,
        alloc,
        environment,
        profile.name,
        parse_results.items,
        gate_rows,
        stream_comparison_rows,
        validated_regression_results.items,
        validated_regression_checks,
    );
    defer alloc.free(json);
    try common.writeFile(io, RESULTS_DIR ++ "/latest.json", json);

    var stdout_buffer: [16 * 1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.writeAll("\n");
    try stdout.writeAll(terminal);
    try stdout.writeAll("\n");
    try stdout.flush();

    var failed = false;
    if (std.mem.eql(u8, profile.name, "stable")) {
        for (gate_rows) |g| {
            if (!g.pass) {
                failed = true;
                std.debug.print(
                    "gate fail: {s} ours={d:.2} best={s} {d:.2} ratio={d:.3}\n",
                    .{ g.fixture, g.ours_permissive_mb_s, g.best_external_parser, g.best_external_mb_s, g.external_ratio },
                );
            }
        }
        for (validated_regression_checks) |check| {
            if (!check.pass) {
                failed = true;
                std.debug.print(
                    "validated regression fail: parser={s} fixture={s} reference={s} ratio={d:.3} minimum={d:.3}\n",
                    .{ check.parser, check.fixture, check.reference_fixture, check.reference_ratio, validated_regression_min_reference_ratio },
                );
            }
        }
    }

    std.debug.print("wrote {s}/latest.md and {s}/latest.json\n", .{ RESULTS_DIR, RESULTS_DIR });

    if (failed) return error.BenchmarkGateFailed;

    if (write_baseline) {
        const baseline = try std.fmt.allocPrint(alloc, RESULTS_DIR ++ "/baseline_{s}.json", .{profile.name});
        defer alloc.free(baseline);
        try common.writeFile(io, baseline, json);
        std.debug.print("wrote baseline {s}\n", .{baseline});
    }

    // README tables are publication output, unlike latest.json/latest.md which
    // are useful diagnostics even for a failed run. Publish only after every
    // stable gate has succeeded.
    if (std.mem.eql(u8, profile.name, "stable")) {
        try updateBenchmarkReadmes(io, alloc, environment, profile.name, parse_results.items, gate_rows, stream_comparison_rows);
        if (resume_stable and common.fileExists(io, STABLE_RESUME_PATH)) {
            try std.Io.Dir.cwd().deleteFile(io, STABLE_RESUME_PATH);
        }
    }
}

fn toolCommandExists(name: []const u8) bool {
    for (tool_command_names) |command| {
        if (std.mem.eql(u8, name, command)) return true;
    }
    return false;
}

fn buildStepExists(build_source: []const u8, name: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, build_source, i, "b.step(\"")) |start| {
        const value_start = start + "b.step(\"".len;
        const value_end = std.mem.indexOfScalarPos(u8, build_source, value_start, '"') orelse return false;
        if (std.mem.eql(u8, build_source[value_start..value_end], name)) return true;
        i = value_end + 1;
    }
    return false;
}

fn localLinkExists(io: std.Io, alloc: std.mem.Allocator, doc_path: []const u8, raw_target: []const u8) !bool {
    var target = std.mem.trim(u8, raw_target, " \t\r\n");
    if (target.len >= 2 and target[0] == '<' and target[target.len - 1] == '>') target = target[1 .. target.len - 1];
    if (target.len == 0 or target[0] == '#') return true;
    if (std.mem.startsWith(u8, target, "http://") or
        std.mem.startsWith(u8, target, "https://") or
        std.mem.startsWith(u8, target, "mailto:") or
        std.mem.startsWith(u8, target, "data:")) return true;

    if (std.mem.indexOfScalar(u8, target, '#')) |hash| target = target[0..hash];
    if (std.mem.indexOfScalar(u8, target, '?')) |query| target = target[0..query];
    if (target.len == 0) return true;

    const base = std.fs.path.dirname(doc_path) orelse ".";
    const path = try std.fs.path.join(alloc, &.{ base, target });
    defer alloc.free(path);
    return common.fileExists(io, path);
}

fn validateMarkdownLinks(io: std.Io, alloc: std.mem.Allocator, doc_path: []const u8, contents: []const u8) !void {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, contents, i, "](")) |start| {
        const target_start = start + 2;
        const target_end = std.mem.indexOfScalarPos(u8, contents, target_start, ')') orelse {
            std.debug.print("docs-check: unterminated markdown link in {s}\n", .{doc_path});
            return error.DocumentationCheckFailed;
        };
        const target = contents[target_start..target_end];
        if (!try localLinkExists(io, alloc, doc_path, target)) {
            std.debug.print("docs-check: missing local link target in {s}: {s}\n", .{ doc_path, target });
            return error.DocumentationCheckFailed;
        }
        i = target_end + 1;
    }
}

fn nextCommandToken(contents: []const u8, start: usize) []const u8 {
    var end = start;
    while (end < contents.len) : (end += 1) {
        const c = contents[end];
        if (c == ' ' or c == '\t' or c == '\r' or c == '\n' or c == '`') break;
    }
    return contents[start..end];
}

fn validateDocumentedCommands(build_source: []const u8, doc_path: []const u8, contents: []const u8) !void {
    const build_prefix = "zig build ";
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, contents, i, build_prefix)) |start| {
        const step_start = start + build_prefix.len;
        const step = nextCommandToken(contents, step_start);
        if (step.len == 0 or step[0] == '-') {
            i = step_start + @max(step.len, 1);
            continue;
        }
        if (!buildStepExists(build_source, step)) {
            std.debug.print("docs-check: undocumented build step implementation for `{s}` referenced by {s}\n", .{ step, doc_path });
            return error.DocumentationCheckFailed;
        }
        i = step_start + step.len;
    }

    const tools_prefix = "zig build tools -- ";
    i = 0;
    while (std.mem.indexOfPos(u8, contents, i, tools_prefix)) |start| {
        const command_start = start + tools_prefix.len;
        const command = nextCommandToken(contents, command_start);
        if (!toolCommandExists(command)) {
            std.debug.print("docs-check: unknown zxml-tools command `{s}` referenced by {s}\n", .{ command, doc_path });
            return error.DocumentationCheckFailed;
        }
        i = command_start + @max(command.len, 1);
    }
}

fn docsCheck(io: std.Io, alloc: std.mem.Allocator) !void {
    const build_source = try common.readFileAlloc(io, alloc, "build.zig");
    defer alloc.free(build_source);

    for (documentation_files) |doc_path| {
        const contents = try common.readFileAlloc(io, alloc, doc_path);
        defer alloc.free(contents);
        try validateMarkdownLinks(io, alloc, doc_path, contents);
        try validateDocumentedCommands(build_source, doc_path, contents);
    }
    std.debug.print("docs-check: {d} markdown files validated\n", .{documentation_files.len});
}

fn examplesCheck(io: std.Io, alloc: std.mem.Allocator) !void {
    try common.ensureDir(io, TMP_SCRATCH_DIR);
    const config_path = TMP_SCRATCH_DIR ++ "/examples_config.zig";
    try common.writeFile(io, config_path,
        \\pub const IntLen = enum { u16, u32, u64, usize };
        \\pub const intlen: IntLen = .u32;
        \\
    );

    var dir = try std.Io.Dir.cwd().openDir(io, "examples", .{ .iterate = true });
    defer dir.close(io);
    var it = dir.iterate();
    var examples = std.ArrayList([]const u8).empty;
    defer {
        for (examples.items) |name| alloc.free(name);
        examples.deinit(alloc);
    }
    while (try it.next(io)) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".zig")) continue;
        try examples.append(alloc, try alloc.dupe(u8, entry.name));
    }
    if (examples.items.len == 0) return error.NoExamplesFound;
    std.mem.sort([]const u8, examples.items, {}, struct {
        fn lessThan(_: void, a: []const u8, b: []const u8) bool {
            return std.mem.order(u8, a, b) == .lt;
        }
    }.lessThan);

    for (examples.items) |name| {
        const example_path = try std.fmt.allocPrint(alloc, "examples/{s}", .{name});
        defer alloc.free(example_path);
        const root_arg = try std.fmt.allocPrint(alloc, "-Mroot={s}", .{example_path});
        defer alloc.free(root_arg);
        const zxml_arg = "-Mzxml=src/root.zig";
        const config_arg = try std.fmt.allocPrint(alloc, "-Mconfig={s}", .{config_path});
        defer alloc.free(config_arg);
        try common.runInherit(io, alloc, &.{
            "zig",             "test",   "--dep",  "zxml",     root_arg,
            "--dep",           "config", zxml_arg, config_arg, "--test-runner",
            "test_runner.zig",
        }, REPO_ROOT);
    }
    std.debug.print("examples-check: {d} example(s) compiled and executed\n", .{examples.items.len});
}

fn writeInterleavedCases(io: std.Io, alloc: std.mem.Allocator, profile: Profile) ![]u8 {
    try common.ensureDir(io, TMP_SCRATCH_DIR);
    const path = try std.fmt.allocPrint(alloc, TMP_SCRATCH_DIR ++ "/interleaved-{s}.json", .{profile.name});
    errdefer alloc.free(path);

    var out = std.ArrayList(u8).empty;
    defer out.deinit(alloc);
    try out.appendSlice(alloc, "[\n");
    for (profile.fixtures, 0..) |fixture, index| {
        const fixture_path = try std.fmt.allocPrint(alloc, FIXTURES_DIR ++ "/{s}", .{fixture.name});
        defer alloc.free(fixture_path);
        if (!common.fileExists(io, fixture_path)) {
            std.debug.print("compare-worktrees: missing fixture {s}; run `zig build tools -- setup-fixtures` first\n", .{fixture_path});
            return error.MissingFixture;
        }
        const row = try std.fmt.allocPrint(
            alloc,
            "  {{\"name\":\"{s}\",\"path\":\"{s}\",\"iterations\":{d}}}{s}\n",
            .{ fixture.name, fixture_path, fixture.iterations, if (index + 1 == profile.fixtures.len) "" else "," },
        );
        defer alloc.free(row);
        try out.appendSlice(alloc, row);
    }
    try out.appendSlice(alloc, "]\n");
    try common.writeFile(io, path, out.items);
    return path;
}

fn compareWorktrees(io: std.Io, alloc: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len < 2) return error.InvalidArguments;
    const base = args[0];
    const candidate = args[1];
    if (std.mem.eql(u8, base, candidate)) return error.InvalidArguments;

    var profile_name: []const u8 = "quick";
    var pair_repeats: usize = 9;
    var core_a: usize = 0;
    var core_b: usize = 2;
    var seed: u64 = interleaved_build_seed;
    var out_path: ?[]const u8 = null;

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--profile")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            profile_name = args[i];
        } else if (std.mem.eql(u8, arg, "--repeats")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            pair_repeats = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--core-a")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            core_a = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--core-b")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            core_b = try std.fmt.parseInt(usize, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--seed")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            seed = try std.fmt.parseInt(u64, args[i], 10);
        } else if (std.mem.eql(u8, arg, "--out")) {
            i += 1;
            if (i >= args.len) return error.InvalidArguments;
            out_path = args[i];
        } else {
            return error.InvalidArguments;
        }
    }
    if (pair_repeats < 3 or pair_repeats % 2 == 0 or core_a == core_b) return error.InvalidArguments;

    const profile = try getProfile(profile_name);
    const cases_path = try writeInterleavedCases(io, alloc, profile);
    defer alloc.free(cases_path);

    for ([_][]const u8{ base, candidate }) |worktree| {
        const build_file = try std.fs.path.join(alloc, &.{ worktree, "build.zig" });
        defer alloc.free(build_file);
        if (!common.fileExists(io, build_file)) {
            std.debug.print("compare-worktrees: not a zxml checkout: {s}\n", .{worktree});
            return error.InvalidWorktree;
        }
        const seed_text = try std.fmt.allocPrint(alloc, "{d}", .{seed});
        defer alloc.free(seed_text);
        try common.runInherit(io, alloc, &.{
            "zig", "build", "bench-only", "-Doptimize=ReleaseFast", "-Dcpu=native", "--seed", seed_text,
        }, worktree);
    }

    const base_bin = try std.fs.path.join(alloc, &.{ base, "zig-out/bin/zxml-bench" });
    defer alloc.free(base_bin);
    const candidate_bin = try std.fs.path.join(alloc, &.{ candidate, "zig-out/bin/zxml-bench" });
    defer alloc.free(candidate_bin);
    const repeats_text = try std.fmt.allocPrint(alloc, "{d}", .{pair_repeats});
    defer alloc.free(repeats_text);
    const core_a_text = try std.fmt.allocPrint(alloc, "{d}", .{core_a});
    defer alloc.free(core_a_text);
    const core_b_text = try std.fmt.allocPrint(alloc, "{d}", .{core_b});
    defer alloc.free(core_b_text);

    var command = std.ArrayList([]const u8).empty;
    defer command.deinit(alloc);
    try command.appendSlice(alloc, &.{
        "python3",      "bench/paired_bench.py",
        "--base",       base_bin,
        "--cand",       candidate_bin,
        "--repeats",    repeats_text,
        "--core-a",     core_a_text,
        "--core-b",     core_b_text,
        "--cases-json", cases_path,
    });
    if (out_path) |path| try command.appendSlice(alloc, &.{ "--out", path });
    try common.runInherit(io, alloc, command.items, REPO_ROOT);
}

fn usage() void {
    std.debug.print(
        \\usage:
        \\  zxml-tools setup-parsers
        \\  zxml-tools setup-fixtures [--refresh]
        \\  zxml-tools run-benchmarks [--profile smoke|quick|stable] [--write-baseline]
        \\  zxml-tools compare-worktrees <base> <candidate> [--profile smoke|quick|stable] [--repeats N] [--core-a N] [--core-b N] [--seed N] [--out path]
        \\  zxml-tools run-conformance [--suite path]...
        \\  zxml-tools docs-check
        \\  zxml-tools examples-check
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

    if (std.mem.eql(u8, cmd, "compare-worktrees")) {
        try compareWorktrees(init.io, alloc, args.items[2..]);
        return;
    }

    if (std.mem.eql(u8, cmd, "run-conformance")) {
        try conformance.runConformance(init.io, alloc, args.items[2..]);
        return;
    }

    if (std.mem.eql(u8, cmd, "docs-check")) {
        if (args.items.len != 2) return error.InvalidArguments;
        try docsCheck(init.io, alloc);
        return;
    }

    if (std.mem.eql(u8, cmd, "examples-check")) {
        if (args.items.len != 2) return error.InvalidArguments;
        try examplesCheck(init.io, alloc);
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
        .parser = "ours-permissive",
        .fixture = "fixture.xml",
        .is_real = true,
        .iterations = 1,
        .samples_ns = &samples,
        .median_ns = 1,
        .throughput_mb_s = 1.0,
    }};

    try std.testing.expectError(error.MissingBenchmarkResult, evaluateGateRows(alloc, profile, &incomplete));
    try std.testing.expectError(error.MissingBenchmarkResult, evaluateStreamComparisonRows(alloc, profile, &incomplete));
}

fn profileHasFixture(profile: Profile, fixture: []const u8) bool {
    for (profile.fixtures) |item| {
        if (std.mem.eql(u8, item.name, fixture)) return true;
    }
    return false;
}

test "headline benchmark profiles exclude diagnostic scan-heavy fixtures" {
    inline for (.{ Profile{ .name = "quick", .fixtures = &quick_fixtures }, Profile{ .name = "stable", .fixtures = &stable_fixtures } }) |profile| {
        try std.testing.expect(!profileHasFixture(profile, "synthetic_long_text.xml"));
        try std.testing.expect(!profileHasFixture(profile, "synthetic_doctype_entities.xml"));
    }
}

test "doctype entity pathology is validated-only and outside headline profiles" {
    try std.testing.expectEqual(@as(usize, 1), validated_regression_fixtures.len);
    try std.testing.expectEqualStrings("synthetic_doctype_entities.xml", validated_regression_fixtures[0].name);
    try std.testing.expectEqualSlices([]const u8, &.{ "ours-validated", "stream-validated" }, &validated_regression_parsers);
    for (validated_regression_parsers) |parser_name| try std.testing.expect(std.mem.indexOf(u8, parser_name, "validated") != null);
}

test "unicode text throughput fixture stays out while unicode names remain" {
    inline for (.{ Profile{ .name = "quick", .fixtures = &quick_fixtures }, Profile{ .name = "stable", .fixtures = &stable_fixtures } }) |profile| {
        try std.testing.expect(!profileHasFixture(profile, "synthetic_unicode_text.xml"));
    }
    try std.testing.expect(profileHasFixture(.{ .name = "stable", .fixtures = &stable_fixtures }, "synthetic_unicode_names.xml"));
}

test "documented command validator accepts build and tool commands" {
    const source =
        \\const a = b.step("test", "Run tests");
        \\const b2 = b.step("tools", "Run tools");
    ;
    try validateDocumentedCommands(source, "README.md", "`zig build test` and `zig build tools -- docs-check`");
    try std.testing.expectError(
        error.DocumentationCheckFailed,
        validateDocumentedCommands(source, "README.md", "`zig build missing-step`"),
    );
}
