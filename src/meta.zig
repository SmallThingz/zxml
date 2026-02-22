const std = @import("std");
const builtin = @import("builtin");

/// converts ascii to unsigned int of appropriate size
pub fn asUint(comptime string: anytype) std.meta.Int(.unsigned, blk: {
  const pi = @typeInfo(@TypeOf(string)).pointer;
  std.debug.assert(pi.size == .slice or (pi.size == .one and @typeInfo(pi.child) == .array));
  const size = if (pi.size == .slice) string.len * @sizeOf(pi.child) else @sizeOf(pi.child);
  break :blk size * 8;
}) {
  const pi = @typeInfo(@TypeOf(string)).pointer;
  std.debug.assert(pi.size == .slice or (pi.size == .one and @typeInfo(pi.child) == .array));
  const size = if (pi.size == .slice) string.len * @sizeOf(pi.child) else @sizeOf(pi.child);

  return @bitCast(string[0 .. size].*);
}

pub const TableStub = struct {pub fn get(_: u8) bool {unreachable;}};

pub fn Table(of: []const u8, len: comptime_int) type {
  if (of.len <= (if (builtin.mode == .ReleaseSmall) 4 else 2)) return struct {
    pub fn get(key: u8) bool {
      if (comptime of.len == 0) return false;
      var retval = key == of[0];
      inline for (of[1 ..]) |c| retval |= c == key;
      return retval;
    }
  } else if (builtin.mode == .ReleaseSmall) return struct {
    const Uint = std.meta.Int(.unsigned, len);
    const set: Uint = blk: {
      var _set: Uint = 0;
      for (of) |c| _set |= @as(Uint, 1) << c;
      break :blk _set;
    };

    pub fn get(key: u8) bool {
      return (set >> key) & 1 != 0;
    }
  } else return struct {
    const set: [len]bool = blk: {
      var _set: [len]bool = [_]bool{false} ** len;
      for (of) |c| _set[c] = true;
      break :blk _set;
    };

    pub fn get(key: u8) bool {
      return set[key];
    }
  };
}

