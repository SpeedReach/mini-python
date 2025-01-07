const std = @import("std");

const Variable = @import("./ssa.zig").Variable;

pub const VariableCounter = struct {
    global_vars: *const std.StringHashMap(void),
    counter: std.StringHashMap(u32),
    stack: std.StringHashMap(std.ArrayList(u32)),

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, global_vars: *const std.StringHashMap(void)) VariableCounter {
        return VariableCounter{
            .global_vars = global_vars,
            .counter = std.StringHashMap(u32).init(allocator),
            .stack = std.StringHashMap(std.ArrayList(u32)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.counter.deinit();
        var it = self.stack.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
    }

    pub fn getLatest(self: Self, base: []const u8) ?Variable {
        const stack = self.stack.get(base);
        if (stack == null) {
            return null;
        }
        const version = stack.?.getLastOrNull();
        if (version == null) {
            return null;
        }
        return Variable{ .base = base, .version = version.? };
    }

    pub fn isGlobal(self: Self, base: []const u8) bool {
        return self.global_vars.get(base) != null;
    }

    pub fn getLatestOrAdd(self: *Self, base: []const u8) !Variable {
        return self.getLatest(base) orelse self.add(base);
    }

    pub fn popUntil(self: *Self, base: []const u8, version: u32) !void {
        const w = self.stack.getPtr(base);
        if (w == null) {
            return;
        }
        const stack = w.?;
        while (stack.*.items.len > 0) {
            const top = stack.*.items[stack.*.items.len - 1];
            if (top == version) {
                break;
            }
            _ = stack.*.pop();
        }
    }

    pub fn add(self: *Self, base: []const u8) !Variable {
        if (self.stack.get(base) == null) {
            try self.stack.put(base, std.ArrayList(u32).init(self.counter.allocator));
        }

        const counter = try self.counter.getOrPutValue(base, 0);
        counter.value_ptr.* += 1;
        const version = counter.value_ptr.*;
        try self.stack.getPtr(base).?.*.append(version);
        return Variable{ .base = base, .version = version };
    }
};
