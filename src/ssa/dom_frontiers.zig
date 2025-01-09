const cfgir = @import("../cfgir/cfgir.zig");
const tree = @import("./dom_tree.zig");

const std = @import("std");
const HashSet = @import("../ds/set.zig").HashSet;

pub const DominaceFrontiers = std.AutoHashMap(u32, HashSet(u32));
pub const DominanceTree = tree.DominanceTree;
pub const computeDominanceTree = tree.computeDominanceTree;
pub const DominanceNode = tree.DominanceNode;

pub fn computeDominaceFrontiers(allocator: std.mem.Allocator, dominaceTree: tree.DominanceTree, cfg: cfgir.ControlFlowGraph) !DominaceFrontiers {
    var frontiers = DominaceFrontiers.init(allocator);
    var it = cfg.blocks.iterator();
    while (it.next()) |entry| {
        try frontiers.put(entry.key_ptr.*, HashSet(u32).init(allocator));
    }
    it = cfg.blocks.iterator();

    while (it.next()) |entry| {
        const predecessors = getPredecessors(entry.value_ptr.*.*);
        if (predecessors.items.len <= 1) {
            continue;
        }
        const idom = getIdom(entry.key_ptr.*, dominaceTree);
        std.debug.print("idom of {d} is {any}\n", .{ entry.key_ptr.*, idom });
        for (predecessors.items) |predecessor| {
            var runner: ?u32 = getId(predecessor.*);
            while (runner != idom and runner != null) {
                var df = frontiers.getPtr(runner.?).?;
                try df.add(entry.key_ptr.*);
                runner = getIdom(runner.?, dominaceTree);
            }
        }
    }
    return frontiers;
}

fn getIdom(id: u32, dominaceTree: tree.DominanceTree) ?u32 {
    const idom = dominaceTree.nodes.get(id).?.idom;
    if (idom == null) {
        return null;
    }
    return idom.?.*.id;
}

fn getId(block: cfgir.Block) u32 {
    switch (block) {
        .Decision => return block.Decision.id,
        .Sequential => return block.Sequential.id,
    }
}

fn getPredecessors(block: cfgir.Block) std.ArrayList(*cfgir.Block) {
    switch (block) {
        .Decision => return block.Decision.predecessors,
        .Sequential => return block.Sequential.predecessors,
    }
}
