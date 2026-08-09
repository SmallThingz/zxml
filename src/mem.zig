// SIMD byte-search core adapted from text-mutation/src/mem.zig (MIT).
const std = @import("std");
const builtin = @import("builtin");

const use_vectors = switch (builtin.zig_backend) {
    .stage2_aarch64, .stage2_powerpc, .stage2_riscv64, .stage2_spirv => false,
    else => !builtin.fuzz,
};

pub inline fn findBytePos(slice: []const u8, start: usize, value: u8) ?usize {
    if (start >= slice.len) return null;
    var i = start;

    if (use_vectors and !std.debug.inValgrind() and !@inComptime()) {
        if (std.simd.suggestVectorLength(u8)) |block_len| {
            const Block = @Vector(block_len, u8);
            const needle: Block = @splat(value);
            while (i + 2 * block_len <= slice.len) {
                inline for (0..2) |_| {
                    const bytes: Block = slice[i..][0..block_len].*;
                    const matches = bytes == needle;
                    if (@reduce(.Or, matches)) return i + std.simd.firstTrue(matches).?;
                    i += block_len;
                }
            }
            inline for (0..2) |shift| {
                const len = block_len / (1 << shift);
                comptime if (len < 4) break;
                const Tail = @Vector(len, u8);
                if (i + len <= slice.len) {
                    const bytes: Tail = slice[i..][0..len].*;
                    const matches = bytes == @as(Tail, @splat(value));
                    if (@reduce(.Or, matches)) return i + std.simd.firstTrue(matches).?;
                    i += len;
                }
            }
        }
    }

    for (slice[i..], i..) |byte, pos| if (byte == value) return pos;
    return null;
}

test "findBytePos handles offsets and vector-sized inputs" {
    var bytes: [257]u8 = @splat('a');
    bytes[0] = '<';
    bytes[127] = '<';
    bytes[256] = '<';
    try std.testing.expectEqual(@as(?usize, 0), findBytePos(&bytes, 0, '<'));
    try std.testing.expectEqual(@as(?usize, 127), findBytePos(&bytes, 1, '<'));
    try std.testing.expectEqual(@as(?usize, 256), findBytePos(&bytes, 128, '<'));
    try std.testing.expectEqual(@as(?usize, null), findBytePos(&bytes, 257, '<'));
}
