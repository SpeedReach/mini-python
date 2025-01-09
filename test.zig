const std = @import("std");

pub fn main() !void {}

test "mem" {
    const allocator = std.testing.allocator;
    var l1 = std.ArrayList(std.ArrayList(u32)).init(allocator);
    var l2 = std.ArrayList(u32).init(allocator);
    try l2.append(1);
    try l1.append(l2);
    defer l1.deinit();
    defer l2.deinit();
    try l2.append(5);

    var l3 = &l1.items[0];
    try l3.append(2);

    std.debug.print("{any}\n", .{l1.items[0].items});
    std.debug.print("{any}\n", .{l2.items});
}
