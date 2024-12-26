const std = @import("std");

/// A Queue implementation using ArrayList as backing storage
pub fn Queue(comptime T: type) type {
    return struct {
        const Self = @This();
        items: std.ArrayList(T),

        /// Initialize a new queue
        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .items = std.ArrayList(T).init(allocator),
            };
        }

        /// Free the queue's memory
        pub fn deinit(self: *Self) void {
            self.items.deinit();
        }

        /// Add an item to the back of the queue
        pub fn enqueue(self: *Self, item: T) std.mem.Allocator.Error!void {
            try self.items.append(item);
        }

        /// Remove and return the item at the front of the queue
        pub fn dequeue(self: *Self) ?T {
            if (self.items.items.len == 0) return null;
            const item = self.items.orderedRemove(0);
            return item;
        }

        /// Look at the front item without removing it
        pub fn peek(self: Self) ?T {
            if (self.items.items.len == 0) return null;
            return self.items.items[0];
        }

        /// Get the current number of items in the queue
        pub fn len(self: Self) usize {
            return self.items.items.len;
        }

        /// Check if the queue is empty
        pub fn isEmpty(self: Self) bool {
            return self.items.items.len == 0;
        }
    };
}
