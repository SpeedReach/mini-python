const dom = @import("./dom.zig");

const std = @import("std");
const HashSet = @import("../ds/set.zig").HashSet;

pub const DominaceFrontiers = std.AutoHashMap(u32, HashSet(u32));
