const std = @import("std");

pub fn HashSet(comptime T: type) type {
    return struct {
        const Self = @This();
        items: std.AutoHashMap(T, void),

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .items = std.AutoHashMap(T, void).init(allocator),
            };
        }
        pub const ItemsIterator = std.AutoHashMap(T, void).KeyIterator;

        pub fn iterator(self: *const Self) ItemsIterator {
            return self.items.keyIterator();
        }

        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        pub fn add(self: *Self, item: T) !void {
            try self.items.put(item, void{});
        }

        pub fn contains(self: Self, item: T) bool {
            return self.items.get(item) != null;
        }

        pub fn remove(self: *Self, item: T) bool {
            return self.items.remove(item);
        }

        /// This does not free keys or values! Be sure to release them if they need deinitialization before calling this function.
        pub fn clear(self: *Self) void {
            self.items.clearAndFree();
        }

        pub fn len(self: Self) u32 {
            return self.items.count();
        }

        pub fn isEmpty(self: Self) bool {
            return self.items.len == 0;
        }
    };
}
