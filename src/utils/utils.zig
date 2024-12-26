pub const pretty = @import("pretty.zig");

const std = @import("std");

pub fn arrayListFromSlice(comptime T: type, allocator: *std.mem.Allocator, slice: []T) std.ArrayList(T) {
    const list = std.ArrayList(T).init(allocator);
    defer list.deinit();
    for (slice) |elem| {
        try list.append(elem);
    }
    return list;
}
