const std = @import("std");
const common = @import("common.zig");
const zxml = @import("zxml");

pub const ConformanceError = error{
    InvalidArguments,
    InvalidSuiteFormat,
    NoSuitesFound,
    ConformanceFailed,
};

const conformance_primary_dir = "bench/conformance";

const SuiteSummary = struct {
    suite_name: []u8,
    total: usize,
    passed: usize,
    failed: usize,
};

pub fn runConformance(io: std.Io, alloc: std.mem.Allocator, args: []const []const u8) !void {
    var suite_paths = std.ArrayList([]u8).empty;
    defer {
        for (suite_paths.items) |p| alloc.free(p);
        suite_paths.deinit(alloc);
    }

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--")) continue;
        if (!std.mem.eql(u8, args[i], "--suite")) return ConformanceError.InvalidArguments;
        i += 1;
        if (i >= args.len) return ConformanceError.InvalidArguments;
        const suite_path = try alloc.dupe(u8, args[i]);
        errdefer alloc.free(suite_path);
        try suite_paths.append(alloc, suite_path);
    }

    if (suite_paths.items.len == 0) {
        try discoverSuites(io, alloc, &suite_paths);
    }

    if (suite_paths.items.len == 0) {
        std.debug.print("no conformance suites found under {s}\n", .{conformance_primary_dir});
        return ConformanceError.NoSuitesFound;
    }

    std.mem.sort([]u8, suite_paths.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    var summaries = std.ArrayList(SuiteSummary).empty;
    defer {
        for (summaries.items) |s| alloc.free(s.suite_name);
        summaries.deinit(alloc);
    }

    var failed_total: usize = 0;

    for (suite_paths.items) |suite_path| {
        const summary = try runSuiteFile(io, alloc, suite_path);
        errdefer alloc.free(summary.suite_name);
        if (summary.failed != 0) failed_total += summary.failed;
        try summaries.append(alloc, summary);
    }

    std.debug.print("\nConformance Summary\n", .{});
    for (summaries.items) |s| {
        std.debug.print("- {s}: {d}/{d} passed ({d} failed)\n", .{ s.suite_name, s.passed, s.total, s.failed });
    }

    if (failed_total != 0) return ConformanceError.ConformanceFailed;
}

fn discoverSuites(io: std.Io, alloc: std.mem.Allocator, out: *std.ArrayList([]u8)) !void {
    _ = try appendSuitesFromDir(io, alloc, out, conformance_primary_dir);
}

fn appendSuitesFromDir(io: std.Io, alloc: std.mem.Allocator, out: *std.ArrayList([]u8), base_dir: []const u8) !usize {
    var dir = std.Io.Dir.cwd().openDir(io, base_dir, .{ .iterate = true }) catch |e| {
        if (e == error.FileNotFound) return 0;
        return e;
    };
    defer dir.close(io);

    var count: usize = 0;
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        const path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ base_dir, entry.name });
        errdefer alloc.free(path);
        try out.append(alloc, path);
        count += 1;
    }

    return count;
}

const SuiteMetadata = struct {
    name: []const u8,
    cases: []const std.json.Value,
};

fn suiteMetadata(root: std.json.Value, suite_path: []const u8) ConformanceError!SuiteMetadata {
    if (root != .object) return ConformanceError.InvalidSuiteFormat;

    var fields = root.object.iterator();
    while (fields.next()) |entry| {
        const key = entry.key_ptr.*;
        if (!std.mem.eql(u8, key, "suite") and !std.mem.eql(u8, key, "cases")) {
            return ConformanceError.InvalidSuiteFormat;
        }
    }

    const suite_name = if (root.object.get("suite")) |value| blk: {
        if (value != .string or value.string.len == 0) return ConformanceError.InvalidSuiteFormat;
        break :blk value.string;
    } else suite_path;

    const cases_value = root.object.get("cases") orelse return ConformanceError.InvalidSuiteFormat;
    if (cases_value != .array or cases_value.array.items.len == 0) {
        return ConformanceError.InvalidSuiteFormat;
    }

    return .{ .name = suite_name, .cases = cases_value.array.items };
}

fn runSuiteFile(io: std.Io, alloc: std.mem.Allocator, suite_path: []const u8) !SuiteSummary {
    const suite_bytes = try common.readFileAlloc(io, alloc, suite_path);
    defer alloc.free(suite_bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, suite_bytes, .{});
    defer parsed.deinit();

    const metadata = try suiteMetadata(parsed.value, suite_path);
    const suite_name = metadata.name;
    const cases_val = metadata.cases;

    const suite_name_owned = try alloc.dupe(u8, suite_name);
    errdefer alloc.free(suite_name_owned);

    var total: usize = 0;
    var passed: usize = 0;
    var failed: usize = 0;

    std.debug.print("\nRunning suite: {s} ({s})\n", .{ suite_name, suite_path });

    for (cases_val, 0..) |case_val, case_idx| {
        total += 1;
        if (case_val != .object) {
            failed += 1;
            std.debug.print("  FAIL case#{d}: case entry is not object\n", .{case_idx});
            continue;
        }

        const result = try runCase(alloc, case_val.object, case_idx);
        defer if (result.reason) |msg| alloc.free(msg);

        if (result.pass) {
            passed += 1;
            std.debug.print("  PASS {s}\n", .{result.case_name});
        } else {
            failed += 1;
            std.debug.print("  FAIL {s}: {s}\n", .{ result.case_name, result.reason.? });
        }
    }

    return .{
        .suite_name = suite_name_owned,
        .total = total,
        .passed = passed,
        .failed = failed,
    };
}

const CaseResult = struct {
    case_name: []const u8,
    pass: bool,
    reason: ?[]u8,
};

fn runCase(alloc: std.mem.Allocator, obj: std.json.ObjectMap, case_idx: usize) !CaseResult {
    const case_name = valueString(obj, "name") orelse "unnamed-case";
    _ = case_idx;

    if (unknownCaseField(obj)) |key| {
        return .{
            .case_name = case_name,
            .pass = false,
            .reason = try std.fmt.allocPrint(alloc, "unknown case field: {s}", .{key}),
        };
    }

    if (invalidCaseFieldType(obj)) |problem| {
        return .{
            .case_name = case_name,
            .pass = false,
            .reason = try std.fmt.allocPrint(alloc, "field {s} must be {s}", .{ problem.key, problem.expected }),
        };
    }

    if (invalidCaseFieldCombination(obj)) |reason| {
        return .{
            .case_name = case_name,
            .pass = false,
            .reason = try alloc.dupe(u8, reason),
        };
    }

    const xml = valueString(obj, "xml") orelse return .{
        .case_name = case_name,
        .pass = false,
        .reason = try alloc.dupe(u8, "missing string field: xml"),
    };
    const spec = CaseSpec{
        .case_name = case_name,
        .xml = xml,
        .expect_ok = valueBool(obj, "expect_ok", true),
        .expect_error = valueString(obj, "expect_error"),
        .expect_nodes = valueInt(obj, "expect_nodes"),
        .expect_elements = valueInt(obj, "expect_elements"),
        .expect_misc_nodes = valueInt(obj, "expect_misc_nodes"),
        .expect_root_name = valueString(obj, "expect_root_name"),
        .expect_first_text = valueString(obj, "expect_first_text"),
        .expect_root_attr_name = valueString(obj, "expect_root_attr_name"),
        .expect_root_attr_value = valueString(obj, "expect_root_attr_value"),
        .expect_unique_root_attrs = valueBoolOpt(obj, "expect_unique_root_attrs"),
        .expect_element_name = valueString(obj, "expect_element_name"),
        .expect_element_min = valueInt(obj, "expect_element_min"),
        .expect_element_max = valueInt(obj, "expect_element_max"),
        .expect_cardinality_valid = valueBoolOpt(obj, "expect_cardinality_valid"),
        .expect_field_name = valueString(obj, "expect_field_name"),
        .expect_field_text = valueString(obj, "expect_field_text"),
        .expect_field_type = valueString(obj, "expect_field_type"),
        .expect_field_type_valid = valueBoolOpt(obj, "expect_field_type_valid"),
        .expect_field_pattern = valueString(obj, "expect_field_pattern"),
        .expect_field_pattern_valid = valueBoolOpt(obj, "expect_field_pattern_valid"),
        .expect_date_before_left = valueString(obj, "expect_date_before_left"),
        .expect_date_before_right = valueString(obj, "expect_date_before_right"),
        .expect_date_before_valid = valueBoolOpt(obj, "expect_date_before_valid"),
    };

    if (obj.get("profiles")) |profiles_val| {
        if (profiles_val != .array) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try alloc.dupe(u8, "profiles must be an array of strings"),
            };
        }
        if (profiles_val.array.items.len == 0) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try alloc.dupe(u8, "profiles array must not be empty"),
            };
        }

        for (profiles_val.array.items) |entry| {
            if (entry != .string) {
                return .{
                    .case_name = case_name,
                    .pass = false,
                    .reason = try alloc.dupe(u8, "profiles entries must be strings"),
                };
            }

            const profile_result = try runCaseWithProfile(alloc, spec, entry.string);
            if (!profile_result.pass) return profile_result;
        }
        return .{ .case_name = case_name, .pass = true, .reason = null };
    }

    const profile = valueString(obj, "profile") orelse "permissive";
    return runCaseWithProfile(alloc, spec, profile);
}

const CaseSpec = struct {
    case_name: []const u8,
    xml: []const u8,
    expect_ok: bool,
    expect_error: ?[]const u8,
    expect_nodes: ?usize,
    expect_elements: ?usize,
    expect_misc_nodes: ?usize,
    expect_root_name: ?[]const u8,
    expect_first_text: ?[]const u8,
    expect_root_attr_name: ?[]const u8,
    expect_root_attr_value: ?[]const u8,
    /// Null means the suite does not care; otherwise require duplicate-root
    /// attribute detection to either pass or fail this case.
    expect_unique_root_attrs: ?bool,
    expect_element_name: ?[]const u8,
    expect_element_min: ?usize,
    expect_element_max: ?usize,
    expect_cardinality_valid: ?bool,
    expect_field_name: ?[]const u8,
    expect_field_text: ?[]const u8,
    expect_field_type: ?[]const u8,
    expect_field_type_valid: ?bool,
    expect_field_pattern: ?[]const u8,
    expect_field_pattern_valid: ?bool,
    expect_date_before_left: ?[]const u8,
    expect_date_before_right: ?[]const u8,
    expect_date_before_valid: ?bool,
};

fn runCaseWithProfile(alloc: std.mem.Allocator, spec: CaseSpec, profile: []const u8) !CaseResult {
    if (std.mem.eql(u8, profile, "permissive")) return runCaseWithOptions(.{}, false, alloc, spec, profile);
    if (std.mem.eql(u8, profile, "validated")) return runCaseWithOptions(.{ .validate_well_formedness = true }, false, alloc, spec, profile);
    if (std.mem.eql(u8, profile, "permissive_misc")) return runCaseWithOptions(.{ .include_misc_nodes = true }, false, alloc, spec, profile);
    if (std.mem.eql(u8, profile, "validated_misc")) return runCaseWithOptions(.{ .validate_well_formedness = true, .include_misc_nodes = true }, false, alloc, spec, profile);
    if (std.mem.eql(u8, profile, "permissive_entities")) return runCaseWithOptions(.{}, true, alloc, spec, profile);
    if (std.mem.eql(u8, profile, "validated_entities")) return runCaseWithOptions(.{ .validate_well_formedness = true }, true, alloc, spec, profile);
    if (std.mem.eql(u8, profile, "permissive_entities_ws")) return runCaseWithOptions(.{ .drop_whitespace_text_nodes = false }, true, alloc, spec, profile);
    if (std.mem.eql(u8, profile, "validated_entities_ws")) return runCaseWithOptions(.{ .validate_well_formedness = true, .drop_whitespace_text_nodes = false }, true, alloc, spec, profile);
    if (std.mem.eql(u8, profile, "permissive_dtd_entities")) return runCaseWithOptions(.{ .expand_dtd_entities = true }, true, alloc, spec, profile);
    if (std.mem.eql(u8, profile, "validated_dtd_entities")) return runCaseWithOptions(.{ .validate_well_formedness = true, .expand_dtd_entities = true }, true, alloc, spec, profile);
    return .{
        .case_name = spec.case_name,
        .pass = false,
        .reason = try std.fmt.allocPrint(alloc, "[{s}] unknown profile", .{profile}),
    };
}

fn runCaseWithOptions(comptime options: zxml.ParseOptions, comptime decode_values: bool, alloc: std.mem.Allocator, spec: CaseSpec, profile: []const u8) !CaseResult {
    const case_name = spec.case_name;
    const expect_ok = spec.expect_ok;
    const expect_error = spec.expect_error;
    const expect_nodes = spec.expect_nodes;
    const expect_elements = spec.expect_elements;
    const expect_misc_nodes = spec.expect_misc_nodes;
    const expect_root_name = spec.expect_root_name;
    const expect_first_text = spec.expect_first_text;
    const expect_root_attr_name = spec.expect_root_attr_name;
    const expect_root_attr_value = spec.expect_root_attr_value;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const case_alloc = arena.allocator();

    const Document = zxml.Types(options).Document;
    var doc = Document.init(case_alloc);
    defer doc.deinit();

    const xml_buf = try case_alloc.dupe(u8, spec.xml);
    defer case_alloc.free(xml_buf);

    var parse_err: ?zxml.ParseError = null;
    const ok = blk: {
        doc.parse(xml_buf) catch |err| {
            parse_err = err;
            break :blk false;
        };

        if (decode_values) {
            validateDecodedProfile(case_alloc, &doc) catch |err| {
                parse_err = err;
                break :blk false;
            };
        }
        break :blk true;
    };

    if (ok != expect_ok) {
        if (ok) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expected parse failure but parse succeeded", .{profile}),
            };
        }
        return .{
            .case_name = case_name,
            .pass = false,
            .reason = try std.fmt.allocPrint(alloc, "[{s}] expected parse success but got error {s}", .{ profile, @errorName(parse_err.?) }),
        };
    }

    if (!ok) {
        if (expect_error) |exp| {
            if (!std.mem.eql(u8, exp, @errorName(parse_err.?))) {
                return .{
                    .case_name = case_name,
                    .pass = false,
                    .reason = try std.fmt.allocPrint(alloc, "[{s}] expected error {s}, got {s}", .{ profile, exp, @errorName(parse_err.?) }),
                };
            }
        }
        return .{ .case_name = case_name, .pass = true, .reason = null };
    }

    if (expect_nodes) |n| {
        if (doc.nodes.items.len != n) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expect_nodes={d}, got {d}", .{ profile, n, doc.nodes.items.len }),
            };
        }
    }

    if (expect_elements) |n| {
        const got = countByKind(&doc, .element);
        if (got != n) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expect_elements={d}, got {d}", .{ profile, n, got }),
            };
        }
    }

    if (expect_misc_nodes) |n| {
        const got = countMisc(&doc);
        if (got != n) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expect_misc_nodes={d}, got {d}", .{ profile, n, got }),
            };
        }
    }

    if (expect_root_name != null or expect_root_attr_name != null or spec.expect_unique_root_attrs != null) {
        const root = firstElement(&doc) orelse {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expected root element, found none", .{profile}),
            };
        };

        if (expect_root_name) |expected| {
            if (!std.mem.eql(u8, root.nameSlice(), expected)) {
                return .{
                    .case_name = case_name,
                    .pass = false,
                    .reason = try std.fmt.allocPrint(alloc, "[{s}] expect_root_name={s}, got {s}", .{ profile, expected, root.nameSlice() }),
                };
            }
        }

        if (expect_root_attr_name) |attr_name| {
            const got = try rootAttributeValue(case_alloc, root, decode_values, attr_name) orelse {
                return .{
                    .case_name = case_name,
                    .pass = false,
                    .reason = try std.fmt.allocPrint(alloc, "[{s}] expected root attr {s}, not found", .{ profile, attr_name }),
                };
            };
            if (expect_root_attr_value) |attr_value| {
                if (!std.mem.eql(u8, got, attr_value)) {
                    return .{
                        .case_name = case_name,
                        .pass = false,
                        .reason = try std.fmt.allocPrint(alloc, "[{s}] expect root attr {s}={s}, got {s}", .{ profile, attr_name, attr_value, got }),
                    };
                }
            }
        }
    }

    if (expect_first_text) |expected| {
        const got = try firstText(case_alloc, &doc, decode_values) orelse {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expected text node, found none", .{profile}),
            };
        };
        if (!std.mem.eql(u8, got, expected)) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expect_first_text={s}, got {s}", .{ profile, expected, got }),
            };
        }
    }

    if ((spec.expect_element_min != null or spec.expect_element_max != null) and spec.expect_element_name == null) {
        return .{
            .case_name = case_name,
            .pass = false,
            .reason = try std.fmt.allocPrint(alloc, "[{s}] expect_element_name required when min/max checks are used", .{profile}),
        };
    }

    if (spec.expect_element_name) |name| {
        const got = countElementsByName(&doc, name);
        var cardinality_ok = true;
        if (spec.expect_element_min) |min| {
            if (got < min) cardinality_ok = false;
        }
        if (spec.expect_element_max) |max| {
            if (got > max) cardinality_ok = false;
        }

        const expected_cardinality_ok = spec.expect_cardinality_valid orelse true;
        if (cardinality_ok != expected_cardinality_ok) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] cardinality check for {s} expected={any} got={any} (count={d}, min={any}, max={any})", .{ profile, name, expected_cardinality_ok, cardinality_ok, got, spec.expect_element_min, spec.expect_element_max }),
            };
        }
    }

    if (spec.expect_unique_root_attrs) |expected_unique| {
        const root = firstElement(&doc) orelse {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expected root element for unique attribute check", .{profile}),
            };
        };
        const actual_unique = hasUniqueAttributes(root);
        if (actual_unique != expected_unique) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] unique root attributes expected={any} got={any}", .{ profile, expected_unique, actual_unique }),
            };
        }
    }

    if ((spec.expect_field_text != null or spec.expect_field_type != null or spec.expect_field_pattern != null) and spec.expect_field_name == null) {
        return .{
            .case_name = case_name,
            .pass = false,
            .reason = try std.fmt.allocPrint(alloc, "[{s}] expect_field_name required when field checks are used", .{profile}),
        };
    }

    if (spec.expect_field_name) |field_name| {
        const field_text = try elementTextByName(case_alloc, &doc, decode_values, field_name) orelse {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expected field {s}, found none", .{ profile, field_name }),
            };
        };

        if (spec.expect_field_text) |expected| {
            if (!std.mem.eql(u8, field_text, expected)) {
                return .{
                    .case_name = case_name,
                    .pass = false,
                    .reason = try std.fmt.allocPrint(alloc, "[{s}] expect_field_text={s}, got {s}", .{ profile, expected, field_text }),
                };
            }
        }

        if (spec.expect_field_type) |field_type| {
            const actual_valid = validateFieldType(field_text, field_type) orelse {
                return .{
                    .case_name = case_name,
                    .pass = false,
                    .reason = try std.fmt.allocPrint(alloc, "[{s}] unknown field type {s}", .{ profile, field_type }),
                };
            };
            const expected_valid = spec.expect_field_type_valid orelse true;
            if (actual_valid != expected_valid) {
                return .{
                    .case_name = case_name,
                    .pass = false,
                    .reason = try std.fmt.allocPrint(alloc, "[{s}] type check for {s} expected={any} got={any} (value={s}, type={s})", .{ profile, field_name, expected_valid, actual_valid, field_text, field_type }),
                };
            }
        }

        if (spec.expect_field_pattern) |pattern| {
            const actual_valid = regexSubsetMatch(field_text, pattern);
            const expected_valid = spec.expect_field_pattern_valid orelse true;
            if (actual_valid != expected_valid) {
                return .{
                    .case_name = case_name,
                    .pass = false,
                    .reason = try std.fmt.allocPrint(alloc, "[{s}] pattern check for {s} expected={any} got={any} (value={s}, pattern={s})", .{ profile, field_name, expected_valid, actual_valid, field_text, pattern }),
                };
            }
        }
    }

    const left_name = spec.expect_date_before_left;
    const right_name = spec.expect_date_before_right;
    if ((left_name != null and right_name == null) or (left_name == null and right_name != null)) {
        return .{
            .case_name = case_name,
            .pass = false,
            .reason = try std.fmt.allocPrint(alloc, "[{s}] both expect_date_before_left/right are required", .{profile}),
        };
    }

    if (left_name) |left_field| {
        const right_field = right_name.?;
        const left_text = try elementTextByName(case_alloc, &doc, decode_values, left_field) orelse {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expected date field {s}, found none", .{ profile, left_field }),
            };
        };
        const right_text = try elementTextByName(case_alloc, &doc, decode_values, right_field) orelse {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expected date field {s}, found none", .{ profile, right_field }),
            };
        };

        const actual_valid = isIsoDate(left_text) and isIsoDate(right_text) and std.mem.lessThan(u8, left_text, right_text);
        const expected_valid = spec.expect_date_before_valid orelse true;
        if (actual_valid != expected_valid) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] date-order check expected={any} got={any} ({s}={s}, {s}={s})", .{ profile, expected_valid, actual_valid, left_field, left_text, right_field, right_text }),
            };
        }
    }

    return .{ .case_name = case_name, .pass = true, .reason = null };
}

fn mapDecodeError(err: anyerror) zxml.ParseError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidNumericCharacterEntity => error.InvalidNumericCharacterEntity,
        error.UnterminatedEntity => error.UnterminatedEntity,
        else => unreachable,
    };
}

fn countByKind(doc: anytype, kind: zxml.NodeType) usize {
    var n: usize = 0;
    for (doc.nodes.items, 0..) |_, i| {
        if (doc.kindAt(@intCast(i)) == kind) n += 1;
    }
    return n;
}

fn countMisc(doc: anytype) usize {
    var n: usize = 0;
    for (doc.nodes.items, 0..) |_, i| {
        switch (doc.kindAt(@intCast(i))) {
            .comment, .cdata, .pi, .declaration, .doctype => n += 1,
            else => {},
        }
    }
    return n;
}

fn countElementsByName(doc: anytype, name: []const u8) usize {
    var n: usize = 0;
    for (doc.nodes.items, 0..) |_, i| {
        if (doc.kindAt(@intCast(i)) != .element) continue;
        if (std.mem.eql(u8, doc.nodeAt(@intCast(i)).?.nameSlice(), name)) n += 1;
    }
    return n;
}

fn firstElement(doc: anytype) ?std.meta.Child(@TypeOf(doc.nodeAt(0))) {
    for (doc.nodes.items, 0..) |_, i| {
        if (doc.kindAt(@intCast(i)) == .element) return doc.nodeAt(@intCast(i));
    }
    return null;
}

fn rootAttributeValue(alloc: std.mem.Allocator, root: anytype, comptime decode_values: bool, name: []const u8) (std.mem.Allocator.Error || zxml.ParseError)!?[]const u8 {
    if (decode_values) {
        const decoded = root.getAttributeValue(alloc, name) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return mapDecodeError(err),
        };
        return if (decoded) |result| result.value else null;
    }
    return root.getAttributeValueRaw(name);
}

fn firstText(alloc: std.mem.Allocator, doc: anytype, comptime decode_values: bool) (std.mem.Allocator.Error || zxml.ParseError)!?[]const u8 {
    for (doc.nodes.items, 0..) |_, i| {
        if (doc.kindAt(@intCast(i)) != .text) continue;
        const text = doc.nodeAt(@intCast(i)).?;
        if (decode_values) {
            const decoded = text.value(alloc) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return mapDecodeError(err),
            };
            return decoded.value;
        }
        return text.valueRawSlice();
    }
    return null;
}

fn elementTextByName(alloc: std.mem.Allocator, doc: anytype, comptime decode_values: bool, name: []const u8) (std.mem.Allocator.Error || zxml.ParseError)!?[]const u8 {
    for (doc.nodes.items, 0..) |_, i| {
        if (doc.kindAt(@intCast(i)) != .element) continue;
        const element = doc.nodeAt(@intCast(i)).?;
        if (!std.mem.eql(u8, element.nameSlice(), name)) continue;

        if (decode_values) {
            const decoded = element.innerText(alloc) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return mapDecodeError(err),
            };
            return decoded.value;
        }

        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(alloc);

        const subtree_end: usize = blk: {
            var cursor = element;
            while (true) {
                if (cursor.nextSibling()) |sibling| break :blk @as(usize, @intCast(sibling.index)) - 1;
                cursor = cursor.parentNode() orelse break :blk doc.nodes.items.len - 1;
            }
        };
        var child_index: usize = @intCast(element.index + 1);
        while (child_index <= subtree_end and child_index < doc.nodes.items.len) : (child_index += 1) {
            const kind = doc.kindAt(@intCast(child_index));
            if (kind == .text or kind == .cdata) {
                try out.appendSlice(alloc, doc.nodeAt(@intCast(child_index)).?.valueRawSlice());
            }
        }
        return try out.toOwnedSlice(alloc);
    }
    return null;
}

fn validateDecodedProfile(alloc: std.mem.Allocator, doc: anytype) zxml.ParseError!void {
    for (doc.nodes.items, 0..) |_, i| {
        const kind = doc.kindAt(@intCast(i));
        if (kind == .element) {
            const element = doc.nodeAt(@intCast(i)).?;
            var attrs = element.attributes();
            while (attrs.next()) |attr| {
                _ = attr.value(alloc) catch |err| return mapDecodeError(err);
            }
        }
        if (kind != .text) continue;
        const text = doc.nodeAt(@intCast(i)).?;
        _ = text.value(alloc) catch |err| return mapDecodeError(err);
    }
}

fn hasUniqueAttributes(root: anytype) bool {
    var outer = root.attributes();
    var outer_index: usize = 0;
    while (outer.next()) |current| : (outer_index += 1) {
        var inner = root.attributes();
        var inner_index: usize = 0;
        while (inner_index < outer_index) : (inner_index += 1) {
            const previous = inner.next() orelse return false;
            if (std.mem.eql(u8, previous.nameSlice(), current.nameSlice())) return false;
        }
    }
    return true;
}

fn validateFieldType(text: []const u8, field_type: []const u8) ?bool {
    if (std.mem.eql(u8, field_type, "string")) return true;
    if (std.mem.eql(u8, field_type, "int")) return isAsciiInt(text);
    if (std.mem.eql(u8, field_type, "date")) return isIsoDate(text);
    return null;
}

fn isAsciiInt(text: []const u8) bool {
    if (text.len == 0) return false;
    var i: usize = 0;
    if (text[0] == '+' or text[0] == '-') {
        i = 1;
        if (i >= text.len) return false;
    }
    while (i < text.len) : (i += 1) {
        if (!std.ascii.isDigit(text[i])) return false;
    }
    return true;
}

fn isIsoDate(text: []const u8) bool {
    if (text.len != 10) return false;
    if (text[4] != '-' or text[7] != '-') return false;

    var i: usize = 0;
    while (i < text.len) : (i += 1) {
        if (i == 4 or i == 7) continue;
        if (!std.ascii.isDigit(text[i])) return false;
    }

    const year = std.fmt.parseUnsigned(u16, text[0..4], 10) catch return false;
    const month = std.fmt.parseUnsigned(u8, text[5..7], 10) catch return false;
    const day = std.fmt.parseUnsigned(u8, text[8..10], 10) catch return false;

    if (month < 1 or month > 12) return false;
    const leap = year % 4 == 0 and (year % 100 != 0 or year % 400 == 0);
    const max_day: u8 = switch (month) {
        2 => if (leap) 29 else 28,
        4, 6, 9, 11 => 30,
        else => 31,
    };
    if (day < 1 or day > max_day) return false;
    return true;
}

test "isIsoDate validates month lengths and leap years" {
    try std.testing.expect(isIsoDate("2024-02-29"));
    try std.testing.expect(!isIsoDate("2023-02-29"));
    try std.testing.expect(!isIsoDate("2024-02-30"));
    try std.testing.expect(!isIsoDate("2024-04-31"));
    try std.testing.expect(!isIsoDate("2024-13-01"));
    try std.testing.expect(!isIsoDate("2024-00-01"));
}

test "regexSubsetMatch honors start and end anchors" {
    try std.testing.expect(regexSubsetMatch("xxABCyy", "ABC"));
    try std.testing.expect(regexSubsetMatch("ABCyy", "^ABC"));
    try std.testing.expect(!regexSubsetMatch("xxABC", "^ABC"));
    try std.testing.expect(regexSubsetMatch("xxABC", "ABC$"));
    try std.testing.expect(!regexSubsetMatch("ABCyy", "ABC$"));
    try std.testing.expect(regexSubsetMatch("ABC", "^ABC$"));
    try std.testing.expect(!regexSubsetMatch("xABC", "^ABC$"));
    try std.testing.expect(regexSubsetMatch("price$", "\\$"));
}

fn regexSubsetMatch(text: []const u8, pattern: []const u8) bool {
    // This intentionally supports only the small regex subset used by the
    // conformance fixtures: anchors, character classes, literals, escapes,
    // and fixed `{n}` repetition.
    var p_start: usize = 0;
    var p_end: usize = pattern.len;

    const anchored_start = p_start < p_end and pattern[p_start] == '^';
    if (anchored_start) p_start += 1;
    const anchored_end = p_end > p_start and pattern[p_end - 1] == '$' and !isEscaped(pattern, p_end - 1);
    if (anchored_end) p_end -= 1;

    if (anchored_start) {
        const match_end = regexSubsetMatchAt(text, pattern[p_start..p_end], 0) orelse return false;
        return !anchored_end or match_end == text.len;
    }

    var start: usize = 0;
    while (start <= text.len) : (start += 1) {
        const match_end = regexSubsetMatchAt(text, pattern[p_start..p_end], start) orelse continue;
        if (!anchored_end or match_end == text.len) return true;
    }
    return false;
}

fn regexSubsetMatchAt(text: []const u8, pattern: []const u8, start: usize) ?usize {
    var t = start;
    var p: usize = 0;

    while (p < pattern.len) {
        var use_class = false;
        var class_spec: []const u8 = "";
        var literal: u8 = 0;

        if (pattern[p] == '[') {
            const close = std.mem.indexOfScalarPos(u8, pattern, p + 1, ']') orelse return null;
            class_spec = pattern[p + 1 .. close];
            if (class_spec.len == 0) return null;
            use_class = true;
            p = close + 1;
        } else if (pattern[p] == '\\') {
            p += 1;
            if (p >= pattern.len) return null;
            literal = pattern[p];
            p += 1;
        } else {
            literal = pattern[p];
            p += 1;
        }

        var repeat: usize = 1;
        if (p < pattern.len and pattern[p] == '{') {
            p += 1;
            const num_start = p;
            while (p < pattern.len and std.ascii.isDigit(pattern[p])) : (p += 1) {}
            if (num_start == p) return null;
            if (p >= pattern.len or pattern[p] != '}') return null;
            repeat = std.fmt.parseUnsigned(usize, pattern[num_start..p], 10) catch return null;
            p += 1;
        }

        var r: usize = 0;
        while (r < repeat) : (r += 1) {
            if (t >= text.len) return null;
            const ch = text[t];
            if (use_class) {
                if (!charClassMatch(class_spec, ch)) return null;
            } else if (ch != literal) {
                return null;
            }
            t += 1;
        }
    }

    return t;
}

fn isEscaped(input: []const u8, pos: usize) bool {
    var backslashes: usize = 0;
    var i = pos;
    while (i > 0 and input[i - 1] == '\\') : (i -= 1) backslashes += 1;
    return backslashes % 2 == 1;
}

fn charClassMatch(spec: []const u8, ch: u8) bool {
    var i: usize = 0;
    while (i < spec.len) {
        if (i + 2 < spec.len and spec[i + 1] == '-') {
            if (ch >= spec[i] and ch <= spec[i + 2]) return true;
            i += 3;
            continue;
        }

        if (ch == spec[i]) return true;
        i += 1;
    }

    return false;
}

fn valueString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const v = obj.get(key) orelse return null;
    if (v != .string) return null;
    return v.string;
}

fn valueBool(obj: std.json.ObjectMap, key: []const u8, default: bool) bool {
    const v = obj.get(key) orelse return default;
    if (v != .bool) return default;
    return v.bool;
}

fn valueBoolOpt(obj: std.json.ObjectMap, key: []const u8) ?bool {
    const v = obj.get(key) orelse return null;
    if (v != .bool) return null;
    return v.bool;
}

fn valueInt(obj: std.json.ObjectMap, key: []const u8) ?usize {
    const v = obj.get(key) orelse return null;
    if (v == .integer and v.integer >= 0) return std.math.cast(usize, v.integer);
    return null;
}

const FieldTypeProblem = struct {
    key: []const u8,
    expected: []const u8,
};

fn isKnownCaseField(key: []const u8) bool {
    const known_fields = [_][]const u8{
        "name",
        "xml",
        "profile",
        "profiles",
        "expect_ok",
        "expect_error",
        "expect_nodes",
        "expect_elements",
        "expect_misc_nodes",
        "expect_root_name",
        "expect_first_text",
        "expect_root_attr_name",
        "expect_root_attr_value",
        "expect_unique_root_attrs",
        "expect_element_name",
        "expect_element_min",
        "expect_element_max",
        "expect_cardinality_valid",
        "expect_field_name",
        "expect_field_text",
        "expect_field_type",
        "expect_field_type_valid",
        "expect_field_pattern",
        "expect_field_pattern_valid",
        "expect_date_before_left",
        "expect_date_before_right",
        "expect_date_before_valid",
    };
    inline for (known_fields) |known| {
        if (std.mem.eql(u8, key, known)) return true;
    }
    return false;
}

fn unknownCaseField(obj: std.json.ObjectMap) ?[]const u8 {
    var copy = obj;
    var it = copy.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (!isKnownCaseField(key)) return key;
    }
    return null;
}

fn invalidCaseFieldType(obj: std.json.ObjectMap) ?FieldTypeProblem {
    const string_fields = [_][]const u8{
        "name",
        "xml",
        "profile",
        "expect_error",
        "expect_root_name",
        "expect_first_text",
        "expect_root_attr_name",
        "expect_root_attr_value",
        "expect_element_name",
        "expect_field_name",
        "expect_field_text",
        "expect_field_type",
        "expect_field_pattern",
        "expect_date_before_left",
        "expect_date_before_right",
    };
    inline for (string_fields) |key| {
        if (obj.get(key)) |value| {
            if (value != .string) return .{ .key = key, .expected = "a string" };
        }
    }

    const bool_fields = [_][]const u8{
        "expect_ok",
        "expect_unique_root_attrs",
        "expect_cardinality_valid",
        "expect_field_type_valid",
        "expect_field_pattern_valid",
        "expect_date_before_valid",
    };
    inline for (bool_fields) |key| {
        if (obj.get(key)) |value| {
            if (value != .bool) return .{ .key = key, .expected = "a boolean" };
        }
    }

    const int_fields = [_][]const u8{
        "expect_nodes",
        "expect_elements",
        "expect_misc_nodes",
        "expect_element_min",
        "expect_element_max",
    };
    inline for (int_fields) |key| {
        if (obj.get(key)) |value| {
            if (value != .integer or value.integer < 0 or std.math.cast(usize, value.integer) == null) {
                return .{ .key = key, .expected = "a non-negative integer" };
            }
        }
    }

    return null;
}

fn invalidCaseFieldCombination(obj: std.json.ObjectMap) ?[]const u8 {
    if (obj.get("profile") != null and obj.get("profiles") != null) {
        return "profile and profiles are mutually exclusive";
    }

    if (valueString(obj, "expect_root_attr_value") != null and valueString(obj, "expect_root_attr_name") == null) {
        return "expect_root_attr_value requires expect_root_attr_name";
    }

    if (valueString(obj, "expect_error") != null and valueBool(obj, "expect_ok", true)) {
        return "expect_error requires expect_ok=false";
    }

    if (valueBoolOpt(obj, "expect_cardinality_valid") != null and
        valueInt(obj, "expect_element_min") == null and valueInt(obj, "expect_element_max") == null)
    {
        return "expect_cardinality_valid requires expect_element_min or expect_element_max";
    }

    if (valueBoolOpt(obj, "expect_field_type_valid") != null and valueString(obj, "expect_field_type") == null) {
        return "expect_field_type_valid requires expect_field_type";
    }

    if (valueBoolOpt(obj, "expect_field_pattern_valid") != null and valueString(obj, "expect_field_pattern") == null) {
        return "expect_field_pattern_valid requires expect_field_pattern";
    }

    if (valueBoolOpt(obj, "expect_date_before_valid") != null and
        (valueString(obj, "expect_date_before_left") == null or valueString(obj, "expect_date_before_right") == null))
    {
        return "expect_date_before_valid requires expect_date_before_left and expect_date_before_right";
    }

    return null;
}

test "runCase rejects unknown fields instead of silently ignoring them" {
    const alloc = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"name":"typo","xml":"<r/>","expect_elemnts":99}
    , .{});
    defer parsed.deinit();

    const result = try runCase(alloc, parsed.value.object, 0);
    defer if (result.reason) |reason| alloc.free(reason);
    try std.testing.expect(!result.pass);
    try std.testing.expectEqualStrings("unknown case field: expect_elemnts", result.reason.?);
}

test "runCase rejects wrong-typed optional fields" {
    const alloc = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"name":"bad","xml":"<r/>","expect_ok":"yes"}
    , .{});
    defer parsed.deinit();

    const result = try runCase(alloc, parsed.value.object, 0);
    defer if (result.reason) |reason| alloc.free(reason);
    try std.testing.expect(!result.pass);
    try std.testing.expectEqualStrings("field expect_ok must be a boolean", result.reason.?);
}

test "runCase rejects negative and overflowing count fields" {
    const alloc = std.testing.allocator;

    const negative = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"name":"negative","xml":"<r/>","expect_nodes":-1}
    , .{});
    defer negative.deinit();
    const negative_result = try runCase(alloc, negative.value.object, 0);
    defer if (negative_result.reason) |reason| alloc.free(reason);
    try std.testing.expect(!negative_result.pass);
    try std.testing.expectEqualStrings("field expect_nodes must be a non-negative integer", negative_result.reason.?);
}

test "runCase rejects expectation fields that would otherwise be ignored" {
    const alloc = std.testing.allocator;
    const cases = [_]struct { json: []const u8, reason: []const u8 }{
        .{ .json =
        \\{"name":"profiles","xml":"<r/>","profile":"validated","profiles":["validated"]}
        , .reason = "profile and profiles are mutually exclusive" },
        .{ .json =
        \\{"name":"attr","xml":"<r a='1'/>","expect_root_attr_value":"1"}
        , .reason = "expect_root_attr_value requires expect_root_attr_name" },
        .{ .json =
        \\{"name":"error","xml":"<r/>","expect_error":"ExpectedGt"}
        , .reason = "expect_error requires expect_ok=false" },
        .{ .json =
        \\{"name":"cardinality","xml":"<r/>","expect_cardinality_valid":true}
        , .reason = "expect_cardinality_valid requires expect_element_min or expect_element_max" },
        .{ .json =
        \\{"name":"type","xml":"<r/>","expect_field_type_valid":true}
        , .reason = "expect_field_type_valid requires expect_field_type" },
        .{ .json =
        \\{"name":"pattern","xml":"<r/>","expect_field_pattern_valid":true}
        , .reason = "expect_field_pattern_valid requires expect_field_pattern" },
        .{ .json =
        \\{"name":"dates","xml":"<r/>","expect_date_before_valid":true}
        , .reason = "expect_date_before_valid requires expect_date_before_left and expect_date_before_right" },
    };

    for (cases) |case| {
        const parsed = try std.json.parseFromSlice(std.json.Value, alloc, case.json, .{});
        defer parsed.deinit();
        const result = try runCase(alloc, parsed.value.object, 0);
        defer if (result.reason) |reason| alloc.free(reason);
        try std.testing.expect(!result.pass);
        try std.testing.expectEqualStrings(case.reason, result.reason.?);
    }
}

test "field text checks concatenate text, CDATA, and descendant text" {
    const alloc = std.testing.allocator;

    const raw = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"name":"raw","profile":"validated","xml":"<r><Code>AB<![CDATA[CD]]><b>E</b>F&amp;G</Code></r>","expect_field_name":"Code","expect_field_text":"ABCDEF&amp;G"}
    , .{});
    defer raw.deinit();
    const raw_result = try runCase(alloc, raw.value.object, 0);
    defer if (raw_result.reason) |reason| alloc.free(reason);
    try std.testing.expect(raw_result.pass);

    const decoded = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"name":"decoded","profile":"validated_entities","xml":"<r><Code>AB<![CDATA[CD]]><b>E</b>F&amp;G</Code></r>","expect_field_name":"Code","expect_field_text":"ABCDEF&G"}
    , .{});
    defer decoded.deinit();
    const decoded_result = try runCase(alloc, decoded.value.object, 0);
    defer if (decoded_result.reason) |reason| alloc.free(reason);
    try std.testing.expect(decoded_result.pass);
}

test "raw field text extraction handles deeply nested elements iteratively" {
    const alloc = std.testing.allocator;
    // Each nested level contributes "<x></x>" (7 bytes). Keep the fixture
    // inside the configured span width while still making recursion impractical.
    const fixed_len = "<r><Code>".len + "value".len + "</Code></r>".len;
    const max_depth_for_input = (zxml.MaxInputLen -| fixed_len) / 7;
    const depth = @min(20_000, max_depth_for_input);
    try std.testing.expect(depth >= 1_000);

    var xml = std.ArrayList(u8).empty;
    defer xml.deinit(alloc);
    try xml.appendSlice(alloc, "<r><Code>");
    for (0..depth) |_| try xml.appendSlice(alloc, "<x>");
    try xml.appendSlice(alloc, "value");
    for (0..depth) |_| try xml.appendSlice(alloc, "</x>");
    try xml.appendSlice(alloc, "</Code></r>");

    const Types = zxml.Types(.{ .validate_well_formedness = true });
    var doc = Types.Document.init(alloc);
    defer doc.deinit();
    try doc.parse(xml.items);

    const text = (try elementTextByName(alloc, &doc, false, "Code")).?;
    defer alloc.free(text);
    try std.testing.expectEqualStrings("value", text);
}

test "field text checks distinguish an empty field from a missing field" {
    const alloc = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"name":"empty","xml":"<r><Code/></r>","expect_field_name":"Code","expect_field_text":""}
    , .{});
    defer parsed.deinit();

    const result = try runCase(alloc, parsed.value.object, 0);
    defer if (result.reason) |reason| alloc.free(reason);
    try std.testing.expect(result.pass);
}

test "root attribute expectations do not require a root-name expectation" {
    const alloc = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"name":"attr-only","xml":"<r a='1'/>","expect_root_attr_name":"a","expect_root_attr_value":"1"}
    , .{});
    defer parsed.deinit();

    const result = try runCase(alloc, parsed.value.object, 0);
    defer if (result.reason) |reason| alloc.free(reason);
    try std.testing.expect(result.pass);
}

test "suiteMetadata rejects malformed and empty suite metadata" {
    const alloc = std.testing.allocator;

    const wrong_name = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"suite":42,"cases":[{"xml":"<r/>"}]}
    , .{});
    defer wrong_name.deinit();
    try std.testing.expectError(ConformanceError.InvalidSuiteFormat, suiteMetadata(wrong_name.value, "fallback.json"));

    const empty_name = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"suite":"","cases":[{"xml":"<r/>"}]}
    , .{});
    defer empty_name.deinit();
    try std.testing.expectError(ConformanceError.InvalidSuiteFormat, suiteMetadata(empty_name.value, "fallback.json"));

    const empty_cases = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"suite":"empty","cases":[]}
    , .{});
    defer empty_cases.deinit();
    try std.testing.expectError(ConformanceError.InvalidSuiteFormat, suiteMetadata(empty_cases.value, "fallback.json"));

    const unknown_field = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"suite":"typo","cases":[{"xml":"<r/>"}],"casess":[]}
    , .{});
    defer unknown_field.deinit();
    try std.testing.expectError(ConformanceError.InvalidSuiteFormat, suiteMetadata(unknown_field.value, "fallback.json"));

    const valid = try std.json.parseFromSlice(std.json.Value, alloc,
        \\{"suite":"valid","cases":[{"xml":"<r/>"}]}
    , .{});
    defer valid.deinit();
    const metadata = try suiteMetadata(valid.value, "fallback.json");
    try std.testing.expectEqualStrings("valid", metadata.name);
    try std.testing.expectEqual(@as(usize, 1), metadata.cases.len);
}
