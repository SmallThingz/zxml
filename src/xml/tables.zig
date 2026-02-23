const std = @import("std");

pub const WhitespaceTable = blk: {
    var t = [_]bool{false} ** 256;
    t[' '] = true;
    t['\t'] = true;
    t['\n'] = true;
    t['\r'] = true;
    break :blk t;
};

pub const NameStartTable = blk: {
    var t = [_]bool{false} ** 256;
    for ('A'..('Z' + 1)) |c| t[c] = true;
    for ('a'..('z' + 1)) |c| t[c] = true;
    t['_'] = true;
    t[':'] = true;
    break :blk t;
};

pub const NameCharTable = blk: {
    var t = [_]bool{false} ** 256;
    for ('A'..('Z' + 1)) |c| t[c] = true;
    for ('a'..('z' + 1)) |c| t[c] = true;
    for ('0'..('9' + 1)) |c| t[c] = true;
    t['_'] = true;
    t[':'] = true;
    t['-'] = true;
    t['.'] = true;
    break :blk t;
};

pub const AttrUnquotedValueCharTable = blk: {
    var t = [_]bool{true} ** 256;
    t['<'] = false;
    t['>'] = false;
    t['&'] = false;
    t['"'] = false;
    t['\''] = false;
    t['='] = false;
    t['`'] = false;
    t[' '] = false;
    t['\t'] = false;
    t['\n'] = false;
    t['\r'] = false;
    break :blk t;
};

pub inline fn isWhitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

pub inline fn isNameStart(c: u8) bool {
    return ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c == ':');
}

pub inline fn isNameChar(c: u8) bool {
    return isNameStart(c) or (c >= '0' and c <= '9') or c == '-' or c == '.';
}

pub inline fn isAttrUnquotedValueChar(c: u8) bool {
    return c != '<' and c != '>' and c != '&' and c != '"' and c != '\'' and c != '=' and c != '`' and c != ' ' and c != '\t' and c != '\n' and c != '\r';
}

pub fn eqlAsciiCaseInsensitive(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (std.ascii.toLower(a[i]) != std.ascii.toLower(b[i])) return false;
    }
    return true;
}

pub fn toLowerInPlace(buf: []u8) void {
    for (buf) |*c| {
        c.* = std.ascii.toLower(c.*);
    }
}
