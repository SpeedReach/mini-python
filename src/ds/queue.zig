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
        /// Add an item to the front of the queue
        pub fn pushFront(self: *Self, item: T) std.mem.Allocator.Error!void {
            try self.items.insert(0, item);
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

const testing = std.testing;

test "Queue - initialization" {
    const allocator = testing.allocator;
    var queue = Queue(i32).init(allocator);
    defer queue.deinit();

    try testing.expect(queue.isEmpty());
    try testing.expectEqual(@as(usize, 0), queue.len());
}

test "Queue - basic operations" {
    const allocator = testing.allocator;
    var queue = Queue(i32).init(allocator);
    defer queue.deinit();

    // Test enqueue
    try queue.enqueue(1);
    try queue.enqueue(2);
    try queue.enqueue(3);

    try testing.expectEqual(@as(usize, 3), queue.len());
    try testing.expect(!queue.isEmpty());

    // Test peek
    try testing.expectEqual(@as(i32, 1), queue.peek().?);
    try testing.expectEqual(@as(usize, 3), queue.len()); // Ensure peek doesn't remove

    // Test dequeue
    try testing.expectEqual(@as(i32, 1), queue.dequeue().?);
    try testing.expectEqual(@as(i32, 2), queue.dequeue().?);
    try testing.expectEqual(@as(i32, 3), queue.dequeue().?);

    try testing.expect(queue.isEmpty());
    try testing.expectEqual(@as(usize, 0), queue.len());
}

test "Queue - empty queue operations" {
    const allocator = testing.allocator;
    var queue = Queue(i32).init(allocator);
    defer queue.deinit();

    try testing.expect(queue.peek() == null);
    try testing.expect(queue.dequeue() == null);
}

test "Queue - mixed operations" {
    const allocator = testing.allocator;
    var queue = Queue(i32).init(allocator);
    defer queue.deinit();

    try queue.enqueue(1);
    try testing.expectEqual(@as(i32, 1), queue.peek().?);
    try testing.expectEqual(@as(i32, 1), queue.dequeue().?);
    try testing.expect(queue.isEmpty());

    try queue.enqueue(2);
    try queue.enqueue(3);
    try testing.expectEqual(@as(i32, 2), queue.dequeue().?);
    try queue.enqueue(4);
    try testing.expectEqual(@as(usize, 2), queue.len());
    try testing.expectEqual(@as(i32, 3), queue.peek().?);
}

test "Queue - string type" {
    const allocator = testing.allocator;
    var queue = Queue([]const u8).init(allocator);
    defer queue.deinit();

    try queue.enqueue("hello");
    try queue.enqueue("world");

    try testing.expectEqualStrings("hello", queue.peek().?);
    try testing.expectEqualStrings("hello", queue.dequeue().?);
    try testing.expectEqualStrings("world", queue.dequeue().?);
    try testing.expect(queue.isEmpty());
}

test "Queue - stress test" {
    const allocator = testing.allocator;
    var queue = Queue(usize).init(allocator);
    defer queue.deinit();

    // Enqueue many items
    const n = 1000;
    var i: usize = 0;
    while (i < n) : (i += 1) {
        try queue.enqueue(i);
    }

    try testing.expectEqual(n, queue.len());

    // Dequeue half
    i = 0;
    while (i < n / 2) : (i += 1) {
        try testing.expectEqual(i, queue.dequeue().?);
    }

    // Enqueue more
    i = n;
    while (i < n + 500) : (i += 1) {
        try queue.enqueue(i);
    }

    try testing.expectEqual(n - n / 2 + 500, queue.len());

    // Dequeue all
    i = n / 2;
    while (!queue.isEmpty()) {
        try testing.expectEqual(i, queue.dequeue().?);
        i += 1;
    }
}
