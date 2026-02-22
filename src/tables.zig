const std = @import("std");

/// How many characters do we skip for the given utf8 prefix, 1 is returned for invalid values
pub const UTF_SKIP_LENGTH = blk: {
  var jl: [128]u8 = undefined;
  for (0 .. 128) |v| {
    jl[v] = switch (@clz(~@as(u8, v + 128))) {
      2, 3, 4 => |skip| skip,
      1, 5, 6, 7, 8 => 1,
      else => unreachable,
  };
  }
  break :blk jl;
};

const UTF_SKIP_LENGTH_UNSAFE_256 = blk: {
  const ptr: []const u8 = &UTF_SKIP_LENGTH;
  break :blk (ptr.ptr - 128)[0 .. 256];
};

/// Returns the skip length given the first part of a utf8 codepoint fragment.
/// Asserts that the fragment >= 128
pub inline fn utfSkipLength(codepoint_fragment: u8) u3 {
  std.debug.assert(codepoint_fragment >= 0x8f);
  return UTF_SKIP_LENGTH_UNSAFE_256[codepoint_fragment];
}

pub const HEX_DECODE_ARRAY = blk: {
  var all: [256]u8 = [_]u8{0xff} ** 256;
  for ('0'..('9' + 1)) |c| all[c] = c - '0';
  for ('A'..('F' + 1)) |c| all[c] = c - 'A' + 10;
  for ('a'..('f' + 1)) |c| all[c] = c - 'a' + 10;
  break :blk all;
};

