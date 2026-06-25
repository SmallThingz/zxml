const std = @import("std");
const common = @import("common.zig");
const fastxml = @import("fastxml");

pub const ConformanceError = error{
    InvalidArguments,
    InvalidSuiteFormat,
    InvalidProfile,
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
        try suite_paths.append(alloc, try alloc.dupe(u8, args[i]));
    }

    if (suite_paths.items.len == 0) {
        try discoverSuites(io, alloc, &suite_paths);
    }

    if (suite_paths.items.len == 0) {
        std.debug.print("no conformance suites found under {s}\n", .{conformance_primary_dir});
        return;
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
        try out.append(alloc, path);
        count += 1;
    }

    return count;
}

fn runSuiteFile(io: std.Io, alloc: std.mem.Allocator, suite_path: []const u8) !SuiteSummary {
    const suite_bytes = try common.readFileAlloc(io, alloc, suite_path);
    defer alloc.free(suite_bytes);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, suite_bytes, .{});
    defer parsed.deinit();

    const root = parsed.value;
    if (root != .object) return ConformanceError.InvalidSuiteFormat;

    const suite_name = if (root.object.get("suite")) |v|
        if (v == .string) v.string else suite_path
    else
        suite_path;

    const cases_val = root.object.get("cases") orelse return ConformanceError.InvalidSuiteFormat;
    if (cases_val != .array) return ConformanceError.InvalidSuiteFormat;

    const suite_name_owned = try alloc.dupe(u8, suite_name);

    var total: usize = 0;
    var passed: usize = 0;
    var failed: usize = 0;

    std.debug.print("\nRunning suite: {s} ({s})\n", .{ suite_name, suite_path });

    for (cases_val.array.items, 0..) |case_val, case_idx| {
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

    const profile = valueString(obj, "profile") orelse "turbo_default";
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

    const options: fastxml.ParseOptions = .{};
    const Document = fastxml.Types(options).Document;
    var doc = Document.init(case_alloc);
    defer doc.deinit();

    const xml_buf = try case_alloc.dupe(u8, spec.xml);
    defer case_alloc.free(xml_buf);

    var parse_err: ?fastxml.ParseError = null;
    const ok = blk: {
        parseWithProfile(&doc, xml_buf, profile) catch |err| {
            if (err == ConformanceError.InvalidProfile) {
                break :blk false;
            }
            parse_err = @errorCast(err);
            break :blk false;
        };

        if (profileWantsDecodedValues(profile)) {
            validateDecodedProfile(case_alloc, &doc) catch |err| {
                parse_err = err;
                break :blk false;
            };
        }
        break :blk true;
    };

    if (!ok and parse_err == null) {
        return .{
            .case_name = case_name,
            .pass = false,
            .reason = try std.fmt.allocPrint(alloc, "[{s}] unknown profile", .{profile}),
        };
    }

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

    if (expect_root_name) |expected| {
        const root = firstElement(&doc) orelse {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expected root element, found none", .{profile}),
            };
        };
        if (!std.mem.eql(u8, root.nameSlice(), expected)) {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expect_root_name={s}, got {s}", .{ profile, expected, root.nameSlice() }),
            };
        }

        if (expect_root_attr_name) |attr_name| {
            const got = try rootAttributeValue(case_alloc, root, profile, attr_name) orelse {
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
        const got = try firstText(case_alloc, &doc, profile) orelse {
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
        const field_text = try elementTextByName(case_alloc, &doc, profile, field_name) orelse {
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
        const left_text = try elementTextByName(case_alloc, &doc, profile, left_field) orelse {
            return .{
                .case_name = case_name,
                .pass = false,
                .reason = try std.fmt.allocPrint(alloc, "[{s}] expected date field {s}, found none", .{ profile, left_field }),
            };
        };
        const right_text = try elementTextByName(case_alloc, &doc, profile, right_field) orelse {
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

fn parseWithProfile(doc: anytype, input: []const u8, profile: []const u8) (fastxml.ParseError || ConformanceError)!void {
    if (std.mem.eql(u8, profile, "turbo_default")) {
        try doc.parse(input, .{});
        return;
    }

    if (std.mem.eql(u8, profile, "strict")) {
        try doc.parse(input, .{
            .mode = .strict,
            .validate_closing_tags = true,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "strict_closed")) {
        try doc.parse(input, .{
            .mode = .strict,
            .validate_closing_tags = true,
            .require_closed_elements_on_eof = true,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "strict_entities")) {
        try doc.parse(input, .{
            .mode = .strict,
            .validate_closing_tags = true,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "strict_entities_ws")) {
        try doc.parse(input, .{
            .mode = .strict,
            .validate_closing_tags = true,
            .drop_whitespace_text_nodes = false,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "strict_misc_off")) {
        try doc.parse(input, .{
            .mode = .strict,
            .validate_closing_tags = true,
            .include_misc_nodes = false,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "turbo_misc_off")) {
        try doc.parse(input, .{
            .mode = .turbo,
            .include_misc_nodes = false,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "strict_dtd_entities")) {
        try doc.parse(input, .{
            .mode = .strict,
            .validate_closing_tags = true,
            .expand_dtd_entities = true,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "turbo_dtd_entities")) {
        try doc.parse(input, .{
            .mode = .turbo,
            .expand_dtd_entities = true,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "turbo_entities")) {
        try doc.parse(input, .{
            .mode = .turbo,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "turbo_entities_ws")) {
        try doc.parse(input, .{
            .mode = .turbo,
            .drop_whitespace_text_nodes = false,
        });
        return;
    }

    if (std.mem.eql(u8, profile, "turbo_validate")) {
        try doc.parse(input, .{
            .mode = .turbo,
            .validate_closing_tags = true,
        });
        return;
    }

    return ConformanceError.InvalidProfile;
}

fn profileWantsDecodedValues(profile: []const u8) bool {
    return std.mem.eql(u8, profile, "strict_entities") or
        std.mem.eql(u8, profile, "strict_entities_ws") or
        std.mem.eql(u8, profile, "turbo_entities") or
        std.mem.eql(u8, profile, "turbo_entities_ws") or
        std.mem.eql(u8, profile, "strict_dtd_entities") or
        std.mem.eql(u8, profile, "turbo_dtd_entities");
}

fn mapDecodeError(err: anyerror) fastxml.ParseError {
    return switch (err) {
        error.InvalidNumericCharacterEntity => error.InvalidNumericCharacterEntity,
        error.UnterminatedEntity => error.UnterminatedEntity,
        else => unreachable,
    };
}

fn countByKind(doc: anytype, kind: fastxml.NodeType) usize {
    var n: usize = 0;
    for (doc.nodes.items) |node| {
        if (node.kind == kind) n += 1;
    }
    return n;
}

fn countMisc(doc: anytype) usize {
    var n: usize = 0;
    for (doc.nodes.items) |node| {
        switch (node.kind) {
            .comment, .cdata, .pi, .declaration, .doctype => n += 1,
            else => {},
        }
    }
    return n;
}

fn countElementsByName(doc: anytype, name: []const u8) usize {
    var n: usize = 0;
    for (doc.nodes.items) |node| {
        if (node.kind != .element) continue;
        if (std.mem.eql(u8, node.name.slice(doc.source), name)) n += 1;
    }
    return n;
}

fn firstElement(doc: anytype) ?std.meta.Child(@TypeOf(doc.nodeAt(0))) {
    for (doc.nodes.items, 0..) |node, i| {
        if (node.kind == .element) return doc.nodeAt(@intCast(i));
    }
    return null;
}

fn rootAttributeValue(alloc: std.mem.Allocator, root: anytype, profile: []const u8, name: []const u8) (std.mem.Allocator.Error || fastxml.ParseError)!?[]const u8 {
    if (profileWantsDecodedValues(profile)) {
        return root.getAttributeValue(alloc, name) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            else => mapDecodeError(err),
        };
    }
    return root.getAttributeValueRaw(name);
}

fn firstText(alloc: std.mem.Allocator, doc: anytype, profile: []const u8) (std.mem.Allocator.Error || fastxml.ParseError)!?[]const u8 {
    for (doc.nodes.items, 0..) |node, i| {
        if (node.kind != .text) continue;
        const text = doc.nodeAt(@intCast(i)).?;
        if (profileWantsDecodedValues(profile)) {
            return text.value(alloc) catch |err| switch (err) {
                error.OutOfMemory => error.OutOfMemory,
                else => mapDecodeError(err),
            };
        }
        return text.valueRawSlice();
    }
    return null;
}

fn elementTextByName(alloc: std.mem.Allocator, doc: anytype, profile: []const u8, name: []const u8) (std.mem.Allocator.Error || fastxml.ParseError)!?[]const u8 {
    for (doc.nodes.items, 0..) |node, i| {
        if (node.kind != .element) continue;
        if (!std.mem.eql(u8, node.name.slice(doc.source), name)) continue;

        var child = doc.nodeAt(@intCast(i)).?.firstChild();
        while (child) |n| : (child = n.nextSibling()) {
            if (n.kind != .text) continue;
            if (profileWantsDecodedValues(profile)) {
                return n.value(alloc) catch |err| switch (err) {
                    error.OutOfMemory => error.OutOfMemory,
                    else => mapDecodeError(err),
                };
            }
            return n.valueRawSlice();
        }
        return null;
    }
    return null;
}

fn validateDecodedProfile(alloc: std.mem.Allocator, doc: anytype) fastxml.ParseError!void {
    for (doc.attrs.items, 0..) |_, i| {
        const attr: fastxml.Types(.{}).Attribute = .{
            .doc = doc,
            .index = @intCast(i),
        };
        _ = attr.value(alloc) catch |err| return mapDecodeError(err);
    }

    for (doc.nodes.items, 0..) |node, i| {
        if (node.kind != .text) continue;
        const text = doc.nodeAt(@intCast(i)).?;
        _ = text.value(alloc) catch |err| return mapDecodeError(err);
    }
}

fn hasUniqueAttributes(root: anytype) bool {
    const attrs = root.doc.attrs.items;
    const start = root.attr_start;
    const end = root.attr_start + root.attr_len;

    var i = start;
    while (i < end) : (i += 1) {
        var j = i + 1;
        while (j < end) : (j += 1) {
            if (std.mem.eql(u8, attrs[i].name.slice(root.doc.source), attrs[j].name.slice(root.doc.source))) {
                return false;
            }
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

    const month = std.fmt.parseUnsigned(u8, text[5..7], 10) catch return false;
    const day = std.fmt.parseUnsigned(u8, text[8..10], 10) catch return false;

    if (month < 1 or month > 12) return false;
    if (day < 1 or day > 31) return false;
    return true;
}

fn regexSubsetMatch(text: []const u8, pattern: []const u8) bool {
    // This intentionally supports only the small regex subset used by the
    // conformance fixtures: anchors, character classes, literals, escapes,
    // and fixed `{n}` repetition.
    var p_start: usize = 0;
    var p_end: usize = pattern.len;

    if (p_start < p_end and pattern[p_start] == '^') p_start += 1;
    if (p_end > p_start and pattern[p_end - 1] == '$') p_end -= 1;

    var t: usize = 0;
    var p = p_start;

    while (p < p_end) {
        var use_class = false;
        var class_spec: []const u8 = "";
        var literal: u8 = 0;

        if (pattern[p] == '[') {
            const close = std.mem.indexOfScalarPos(u8, pattern, p + 1, ']') orelse return false;
            if (close >= p_end) return false;
            class_spec = pattern[p + 1 .. close];
            if (class_spec.len == 0) return false;
            use_class = true;
            p = close + 1;
        } else if (pattern[p] == '\\') {
            p += 1;
            if (p >= p_end) return false;
            literal = pattern[p];
            p += 1;
        } else {
            literal = pattern[p];
            p += 1;
        }

        var repeat: usize = 1;
        if (p < p_end and pattern[p] == '{') {
            p += 1;
            const num_start = p;
            while (p < p_end and std.ascii.isDigit(pattern[p])) : (p += 1) {}
            if (num_start == p) return false;
            if (p >= p_end or pattern[p] != '}') return false;
            repeat = std.fmt.parseUnsigned(usize, pattern[num_start..p], 10) catch return false;
            p += 1;
        }

        var r: usize = 0;
        while (r < repeat) : (r += 1) {
            if (t >= text.len) return false;
            const ch = text[t];
            if (use_class) {
                if (!charClassMatch(class_spec, ch)) return false;
            } else {
                if (ch != literal) return false;
            }
            t += 1;
        }
    }

    return t == text.len;
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
    if (v == .integer and v.integer >= 0) return @intCast(v.integer);
    return null;
}
