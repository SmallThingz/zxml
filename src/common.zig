const std = @import("std");
const config = @import("config");

pub const IndexInt = switch (config.intlen) {
    .u16 => u16,
    .u32 => u32,
    .u64 => u64,
    .usize => usize,
};

pub const MaxLen: usize = if (@sizeOf(IndexInt) >= @sizeOf(usize))
    std.math.maxInt(usize)
else
    @as(usize, std.math.maxInt(IndexInt));

pub inline fn lenFits(len: usize) bool {
    return len <= MaxLen;
}

pub const InvalidIndex: IndexInt = std.math.maxInt(IndexInt);

test "IndexInt-derived bounds are self-consistent" {
    try std.testing.expect(lenFits(0));
    try std.testing.expect(lenFits(MaxLen));
    if (MaxLen < std.math.maxInt(usize)) {
        try std.testing.expect(!lenFits(MaxLen + 1));
    }
    try std.testing.expectEqual(std.math.maxInt(IndexInt), InvalidIndex);
}
