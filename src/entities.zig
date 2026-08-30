const std = @import("std");
const tables = @import("tables.zig");

pub const DecodeError = error{
    InvalidNumericCharacterEntity,
    UnterminatedEntity,
    RecursiveEntity,
};

pub const BoundedDecodeError = DecodeError || error{OutputTooLarge};

const ResolveState = enum {
    visiting,
    done,
};

/// Resolves borrowed DTD entity declarations into `resolved`. Declarations may
/// reference entities declared later. Each final replacement value is bounded
/// independently, and recursive entity graphs are rejected.
pub fn resolveEntityDeclarationsBounded(
    alloc: std.mem.Allocator,
    declarations: *const std.StringHashMap([]const u8),
    resolved: *std.StringHashMap([]u8),
    strict: bool,
    max_output_len: usize,
) (std.mem.Allocator.Error || BoundedDecodeError)!void {
    var states = std.StringHashMap(ResolveState).init(alloc);
    defer states.deinit();

    var it = declarations.iterator();
    while (it.next()) |entry| {
        _ = try resolveEntityDeclaration(
            alloc,
            declarations,
            resolved,
            &states,
            entry.key_ptr.*,
            strict,
            max_output_len,
        );
    }
}

const ResolveFrame = struct {
    name: []const u8,
    input: []const u8,
    src: usize = 0,
    out: std.ArrayList(u8) = .empty,
};

fn resolveEntityDeclaration(
    alloc: std.mem.Allocator,
    declarations: *const std.StringHashMap([]const u8),
    resolved: *std.StringHashMap([]u8),
    states: *std.StringHashMap(ResolveState),
    name: []const u8,
    strict: bool,
    max_output_len: usize,
) (std.mem.Allocator.Error || BoundedDecodeError)![]const u8 {
    if (resolved.get(name)) |value| return value;
    if (states.get(name)) |state| switch (state) {
        .done => unreachable,
        .visiting => return error.RecursiveEntity,
    };

    const raw = declarations.get(name) orelse unreachable;
    var frames = std.ArrayList(ResolveFrame).empty;
    defer {
        for (frames.items) |*frame| frame.out.deinit(alloc);
        frames.deinit(alloc);
    }

    try states.put(name, .visiting);
    try frames.append(alloc, .{ .name = name, .input = raw });

    while (frames.items.len != 0) {
        const frame_idx = frames.items.len - 1;
        var pushed_child = false;

        while (frames.items[frame_idx].src < frames.items[frame_idx].input.len) {
            const src = frames.items[frame_idx].src;
            const input = frames.items[frame_idx].input;

            if (input[src] != '&') {
                const next = std.mem.indexOfScalarPos(u8, input, src, '&') orelse input.len;
                try appendLimited(&frames.items[frame_idx].out, alloc, input[src..next], max_output_len);
                frames.items[frame_idx].src = next;
                continue;
            }

            const token = parseEntityToken(input, src) catch |err| switch (err) {
                error.UnterminatedEntity => {
                    if (strict) return error.UnterminatedEntity;
                    try appendLimited(&frames.items[frame_idx].out, alloc, "&", max_output_len);
                    frames.items[frame_idx].src += 1;
                    continue;
                },
                error.InvalidNumericCharacterEntity => {
                    if (strict) return error.InvalidNumericCharacterEntity;
                    try appendLimited(&frames.items[frame_idx].out, alloc, "&", max_output_len);
                    frames.items[frame_idx].src += 1;
                    continue;
                },
            };

            if (try decodeEntityBody(token.body, strict)) |decoded| {
                try appendLimited(&frames.items[frame_idx].out, alloc, decoded.bytes[0..decoded.len], max_output_len);
                frames.items[frame_idx].src += token.consumed;
                continue;
            }

            if (resolved.get(token.body)) |value| {
                try appendLimited(&frames.items[frame_idx].out, alloc, value, max_output_len);
                frames.items[frame_idx].src += token.consumed;
                continue;
            }

            if (declarations.get(token.body)) |child_raw| {
                if (states.get(token.body)) |state| switch (state) {
                    .visiting => return error.RecursiveEntity,
                    .done => unreachable,
                };
                try states.put(token.body, .visiting);
                try frames.append(alloc, .{ .name = token.body, .input = child_raw });
                pushed_child = true;
                break;
            }

            if (strict) return error.InvalidNumericCharacterEntity;
            try appendLimited(&frames.items[frame_idx].out, alloc, "&", max_output_len);
            frames.items[frame_idx].src += 1;
        }

        if (pushed_child) continue;

        const frame_name = frames.items[frame_idx].name;
        const value = try frames.items[frame_idx].out.toOwnedSlice(alloc);
        const owned_name = alloc.dupe(u8, frame_name) catch |err| {
            alloc.free(value);
            return err;
        };
        const gop = resolved.getOrPut(owned_name) catch |err| {
            alloc.free(owned_name);
            alloc.free(value);
            return err;
        };
        if (gop.found_existing) {
            alloc.free(owned_name);
            alloc.free(value);
        } else {
            gop.key_ptr.* = owned_name;
            gop.value_ptr.* = value;
        }
        states.getPtr(frame_name).?.* = .done;
        frames.items.len -= 1;

        if (frames.items.len == 0) return gop.value_ptr.*;
    }

    unreachable;
}

const EntityDecode = struct {
    bytes: [4]u8,
    len: usize,
};

const EntityToken = struct {
    consumed: usize,
    body: []const u8,
};

pub fn decodeAllocWithEntityMap(
    alloc: std.mem.Allocator,
    input: []const u8,
    strict: bool,
    entity_map: ?*const std.StringHashMap([]u8),
) (std.mem.Allocator.Error || DecodeError)![]u8 {
    return decodeAllocWithEntityMapImpl(alloc, input, strict, entity_map, null) catch |err| switch (err) {
        error.OutputTooLarge => unreachable,
        else => |e| return e,
    };
}

pub fn decodeAllocWithEntityMapBounded(
    alloc: std.mem.Allocator,
    input: []const u8,
    strict: bool,
    entity_map: ?*const std.StringHashMap([]u8),
    max_output_len: usize,
) (std.mem.Allocator.Error || BoundedDecodeError)![]u8 {
    return decodeAllocWithEntityMapImpl(alloc, input, strict, entity_map, max_output_len);
}

fn decodeAllocWithEntityMapImpl(
    alloc: std.mem.Allocator,
    input: []const u8,
    strict: bool,
    entity_map: ?*const std.StringHashMap([]u8),
    max_output_len: ?usize,
) (std.mem.Allocator.Error || BoundedDecodeError)![]u8 {
    if (std.mem.indexOfScalar(u8, input, '&') == null) {
        if (max_output_len) |limit| if (input.len > limit) return error.OutputTooLarge;
        return alloc.dupe(u8, input);
    }
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(alloc);
    try appendDecodedWithEntityMapImpl(&out, alloc, input, strict, entity_map, max_output_len);
    return out.toOwnedSlice(alloc);
}

pub fn appendDecodedWithEntityMap(
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    input: []const u8,
    strict: bool,
    entity_map: ?*const std.StringHashMap([]u8),
) (std.mem.Allocator.Error || DecodeError)!void {
    appendDecodedWithEntityMapImpl(out, alloc, input, strict, entity_map, null) catch |err| switch (err) {
        error.OutputTooLarge => unreachable,
        else => |e| return e,
    };
}

fn appendDecodedWithEntityMapImpl(
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    input: []const u8,
    strict: bool,
    entity_map: ?*const std.StringHashMap([]u8),
    max_output_len: ?usize,
) (std.mem.Allocator.Error || BoundedDecodeError)!void {
    const first = std.mem.indexOfScalar(u8, input, '&') orelse {
        try appendLimited(out, alloc, input, max_output_len);
        return;
    };

    try appendLimited(out, alloc, input[0..first], max_output_len);
    var src = first;
    while (src < input.len) {
        if (input[src] != '&') {
            const next = std.mem.indexOfScalarPos(u8, input, src, '&') orelse input.len;
            try appendLimited(out, alloc, input[src..next], max_output_len);
            src = next;
            continue;
        }

        const token = parseEntityToken(input, src) catch |err| switch (err) {
            error.UnterminatedEntity => {
                if (strict) return error.UnterminatedEntity;
                try appendLimited(out, alloc, "&", max_output_len);
                src += 1;
                continue;
            },
            error.InvalidNumericCharacterEntity => {
                if (strict) return error.InvalidNumericCharacterEntity;
                try appendLimited(out, alloc, "&", max_output_len);
                src += 1;
                continue;
            },
        };

        if (try tryAppendDecodedEntityBody(out, alloc, token.body, strict, entity_map, max_output_len)) {
            src += token.consumed;
            continue;
        }

        if (strict) return error.InvalidNumericCharacterEntity;
        try appendLimited(out, alloc, "&", max_output_len);
        src += 1;
    }
}

fn appendLimited(
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    bytes: []const u8,
    max_output_len: ?usize,
) (std.mem.Allocator.Error || error{OutputTooLarge})!void {
    if (max_output_len) |limit| {
        if (out.items.len > limit or bytes.len > limit - out.items.len) return error.OutputTooLarge;
    }
    try out.appendSlice(alloc, bytes);
}

fn tryAppendDecodedEntityBody(
    out: *std.ArrayList(u8),
    alloc: std.mem.Allocator,
    body: []const u8,
    strict: bool,
    entity_map: ?*const std.StringHashMap([]u8),
    max_output_len: ?usize,
) (std.mem.Allocator.Error || BoundedDecodeError)!bool {
    if (try decodeEntityBody(body, strict)) |decoded| {
        try appendLimited(out, alloc, decoded.bytes[0..decoded.len], max_output_len);
        return true;
    }

    if (entity_map) |map| {
        if (map.get(body)) |value| {
            try appendLimited(out, alloc, value, max_output_len);
            return true;
        }
    }

    return false;
}

fn parseEntityToken(noalias buf: []const u8, start: usize) error{ InvalidNumericCharacterEntity, UnterminatedEntity }!EntityToken {
    const semi = std.mem.indexOfScalarPos(u8, buf, start + 1, ';') orelse {
        return error.UnterminatedEntity;
    };

    const body = buf[start + 1 .. semi];
    if (body.len == 0) return error.InvalidNumericCharacterEntity;

    return .{
        .consumed = semi - start + 1,
        .body = body,
    };
}

fn decodeEntityBody(body: []const u8, strict: bool) DecodeError!?EntityDecode {
    const named: ?u8 = if (std.mem.eql(u8, body, "amp"))
        '&'
    else if (std.mem.eql(u8, body, "lt"))
        '<'
    else if (std.mem.eql(u8, body, "gt"))
        '>'
    else if (std.mem.eql(u8, body, "apos"))
        '\''
    else if (std.mem.eql(u8, body, "quot"))
        '"'
    else
        null;
    if (named) |c| {
        return .{
            .bytes = .{ c, 0, 0, 0 },
            .len = 1,
        };
    }

    if (body[0] == '#') {
        const cp: u21 = blk: {
            const text = body[1..];
            if (text.len == 0) {
                if (strict) return error.InvalidNumericCharacterEntity;
                return null;
            }

            const is_hex = text[0] == 'x' or (!strict and text[0] == 'X');
            const digits = if (is_hex) text[1..] else text;
            if (digits.len == 0) {
                if (strict) return error.InvalidNumericCharacterEntity;
                return null;
            }

            var value: u32 = 0;
            for (digits) |c| {
                const d: u8 = if (is_hex)
                    if (c >= '0' and c <= '9')
                        c - '0'
                    else if (c >= 'a' and c <= 'f')
                        c - 'a' + 10
                    else if (c >= 'A' and c <= 'F')
                        c - 'A' + 10
                    else
                        255
                else if (c >= '0' and c <= '9')
                    c - '0'
                else
                    255;

                if (d == 255) {
                    if (strict) return error.InvalidNumericCharacterEntity;
                    return null;
                }
                const base: u32 = if (is_hex) 16 else 10;
                if (value > (0x10FFFF - @as(u32, d)) / base) {
                    if (strict) return error.InvalidNumericCharacterEntity;
                    return null;
                }
                value = value * base + d;
            }

            if (!isValidXmlChar(value)) {
                if (strict) return error.InvalidNumericCharacterEntity;
                return null;
            }
            break :blk @intCast(value);
        };

        var out_bytes: [4]u8 = undefined;
        const written = std.unicode.utf8Encode(cp, &out_bytes) catch {
            if (strict) return error.InvalidNumericCharacterEntity;
            return null;
        };

        return .{
            .bytes = out_bytes,
            .len = written,
        };
    }

    return null;
}

inline fn isValidXmlChar(value: u32) bool {
    return value == 0x9 or value == 0xA or value == 0xD or
        (value >= 0x20 and value <= 0xD7FF) or
        (value >= 0xE000 and value <= 0xFFFD) or
        (value >= 0x10000 and value <= 0x10FFFF);
}

test "decodeAlloc decodes without mutating the source slice" {
    const alloc = std.testing.allocator;
    const input = "&amp;&#65;&#x42;";
    const decoded = try decodeAllocWithEntityMap(alloc, input, true, null);
    defer alloc.free(decoded);

    try std.testing.expectEqualStrings("&AB", decoded);
    try std.testing.expectEqualStrings("&amp;&#65;&#x42;", input);
}

test "non-strict decode leaves malformed and unknown entities literal" {
    const alloc = std.testing.allocator;

    const unknown = try decodeAllocWithEntityMap(alloc, "&bogus; &amp", false, null);
    defer alloc.free(unknown);
    try std.testing.expectEqualStrings("&bogus; &amp", unknown);

    const apost_quot = try decodeAllocWithEntityMap(alloc, "&apos;&quot;", true, null);
    defer alloc.free(apost_quot);
    try std.testing.expectEqualStrings("'\"", apost_quot);
}

test "decodeAllocWithEntityMap expands mapped named entities" {
    const alloc = std.testing.allocator;
    var map = std.StringHashMap([]u8).init(alloc);
    defer {
        var it = map.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    const key = try alloc.dupe(u8, "safe");
    const value = try alloc.dupe(u8, "SAFE");
    try map.put(key, value);

    const decoded = try decodeAllocWithEntityMap(alloc, "&safe;&amp;", true, &map);
    defer alloc.free(decoded);
    try std.testing.expectEqualStrings("SAFE&", decoded);
}

test "strict decode rejects unknown named entities without a DTD map" {
    const alloc = std.testing.allocator;
    try std.testing.expectError(error.InvalidNumericCharacterEntity, decodeAllocWithEntityMap(alloc, "&bogus;", true, null));
}

test "strict decode rejects XML-invalid character references" {
    const alloc = std.testing.allocator;
    inline for (.{ "&#0;", "&#x1f;", "&#xD800;", "&#xFFFE;", "&#X41;", "&#999999999999999999999999999999;", "&#xffffffffffffffffffffffffffffffff;" }) |input| {
        try std.testing.expectError(error.InvalidNumericCharacterEntity, decodeAllocWithEntityMap(alloc, input, true, null));
    }

    const turbo = try decodeAllocWithEntityMap(alloc, "&#X41;", false, null);
    defer alloc.free(turbo);
    try std.testing.expectEqualStrings("A", turbo);
}

test "bounded entity decoding rejects expansion before appending past the cap" {
    const alloc = std.testing.allocator;
    var map = std.StringHashMap([]u8).init(alloc);
    defer {
        var it = map.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
        }
        map.deinit();
    }

    const key = try alloc.dupe(u8, "wide");
    const value = try alloc.dupe(u8, "12345678");
    try map.put(key, value);
    try std.testing.expectError(
        error.OutputTooLarge,
        decodeAllocWithEntityMapBounded(alloc, "&wide;", true, &map, 4),
    );
}

test "entity dependency resolution is iterative for deep declaration chains" {
    const alloc = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const scratch = arena.allocator();

    var declarations = std.StringHashMap([]const u8).init(scratch);
    var resolved = std.StringHashMap([]u8).init(alloc);
    defer {
        var it = resolved.iterator();
        while (it.next()) |entry| {
            alloc.free(entry.key_ptr.*);
            alloc.free(entry.value_ptr.*);
        }
        resolved.deinit();
    }

    const count = 50_000;
    for (0..count) |i| {
        const name = try std.fmt.allocPrint(scratch, "e{d}", .{i});
        const value = if (i + 1 < count)
            try std.fmt.allocPrint(scratch, "&e{d};", .{i + 1})
        else
            try scratch.dupe(u8, "x");
        try declarations.put(name, value);
    }

    try resolveEntityDeclarationsBounded(alloc, &declarations, &resolved, true, 16);
    try std.testing.expectEqualStrings("x", resolved.get("e0").?);
    try std.testing.expectEqual(@as(usize, count), resolved.count());
}
