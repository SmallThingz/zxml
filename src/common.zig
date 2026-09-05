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

/// Inclusive-exclusive byte span into parser source.
pub const Span = struct {
    start: IndexInt = 0,
    end: IndexInt = 0,

    pub inline fn len(self: @This()) IndexInt {
        return self.end - self.start;
    }

    pub inline fn isEmpty(self: @This()) bool {
        return self.start == self.end;
    }

    pub inline fn slice(self: @This(), source: []const u8) []const u8 {
        return source[self.start..self.end];
    }

    pub inline fn sliceMut(self: @This(), source: []u8) []u8 {
        return source[self.start..self.end];
    }

    pub inline fn setEnd(self: *@This(), end_offset: IndexInt) void {
        std.debug.assert(end_offset >= self.start);
        self.end = end_offset;
    }
};

/// Byte-slice result that either borrows document source or owns an allocation.
pub const SliceResult = struct {
    value: []const u8,
    owned: bool = false,

    pub fn free(self: @This(), allocator: std.mem.Allocator) void {
        if (self.owned) allocator.free(self.value);
    }
};

test "IndexInt-derived bounds are self-consistent" {
    try std.testing.expect(lenFits(0));
    try std.testing.expect(lenFits(MaxLen));
    if (MaxLen < std.math.maxInt(usize)) {
        try std.testing.expect(!lenFits(MaxLen + 1));
    }
    try std.testing.expectEqual(std.math.maxInt(IndexInt), InvalidIndex);
}
