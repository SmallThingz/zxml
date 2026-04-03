const std = @import("std");

pub fn fileExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

pub fn ensureDir(io: std.Io, path: []const u8) !void {
    try std.Io.Dir.cwd().createDirPath(io, path);
}

pub fn joinArgs(alloc: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, "+ ");
    for (argv, 0..) |arg, i| {
        if (i != 0) try out.append(alloc, ' ');
        if (std.mem.indexOfScalar(u8, arg, ' ') != null) {
            try out.append(alloc, '"');
            try out.appendSlice(alloc, arg);
            try out.append(alloc, '"');
        } else {
            try out.appendSlice(alloc, arg);
        }
    }
    return out.toOwnedSlice(alloc);
}

pub fn runInherit(io: std.Io, alloc: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) !void {
    const pretty = try joinArgs(alloc, argv);
    defer alloc.free(pretty);
    std.debug.print("{s}\n", .{pretty});

    const cwd_opt: std.process.Child.Cwd = if (cwd) |p| .{ .path = p } else .inherit;
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .cwd = cwd_opt,
        .expand_arg0 = .expand,
        .stdin = .ignore,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.ChildProcessFailed,
        else => return error.ChildProcessFailed,
    }
}

pub fn runCaptureStdout(io: std.Io, alloc: std.mem.Allocator, argv: []const []const u8, cwd: ?[]const u8) ![]u8 {
    const cwd_opt: std.process.Child.Cwd = if (cwd) |p| .{ .path = p } else .inherit;
    const res = try std.process.run(alloc, io, .{
        .argv = argv,
        .cwd = cwd_opt,
        .expand_arg0 = .expand,
        .stdout_limit = .limited(2 * 1024 * 1024),
        .stderr_limit = .limited(2 * 1024 * 1024),
    });
    defer alloc.free(res.stdout);
    defer alloc.free(res.stderr);

    switch (res.term) {
        .exited => |code| if (code != 0) return error.ChildProcessFailed,
        else => return error.ChildProcessFailed,
    }

    if (res.stdout.len != 0) return alloc.dupe(u8, std.mem.trim(u8, res.stdout, " \r\n\t"));
    return alloc.dupe(u8, std.mem.trim(u8, res.stderr, " \r\n\t"));
}

pub fn parseLastInt(text: []const u8) !u64 {
    var i: usize = text.len;
    while (i > 0) : (i -= 1) {
        const c = text[i - 1];
        if (c >= '0' and c <= '9') break;
    }
    if (i == 0) return error.NoIntegerFound;

    var start = i - 1;
    while (start > 0 and text[start - 1] >= '0' and text[start - 1] <= '9') : (start -= 1) {}
    return std.fmt.parseInt(u64, text[start..i], 10);
}

pub fn medianU64(alloc: std.mem.Allocator, vals: []const u64) !u64 {
    if (vals.len == 0) return error.EmptyInput;
    const copy = try alloc.dupe(u64, vals);
    defer alloc.free(copy);
    std.mem.sort(u64, copy, {}, std.sort.asc(u64));
    return copy[copy.len / 2];
}

pub fn writeFile(io: std.Io, path: []const u8, bytes: []const u8) !void {
    try std.Io.Dir.cwd().writeFile(io, .{
        .sub_path = path,
        .data = bytes,
        .flags = .{ .truncate = true },
    });
}

pub fn readFileAlloc(io: std.Io, alloc: std.mem.Allocator, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .unlimited);
}

pub fn nowUnix(io: std.Io) i64 {
    return std.Io.Timestamp.now(io, .real).toSeconds();
}
