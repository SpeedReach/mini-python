const std = @import("std");
const cfgir = @import("../cfgir/cfgir.zig");
const HashSet = @import("../ds/ds.zig").HashSet;

pub const DominanceSet = struct {
    sets: std.AutoHashMap(u32, HashSet(u32)),

    const Self = @This();
    pub fn deinit(self: *Self) void {
        var it = self.sets.valueIterator();
        while (it.next()) |entry| {
            entry.*.deinit();
        }
        self.sets.deinit();
    }
};

pub const DominanceTree = struct {
    root: *DominanceNode,
    nodes: std.AutoHashMap(u32, *DominanceNode),

    const Self = @This();

    pub fn deinit(self: Self) void {
        var it = self.nodes.valueIterator();
        while (it.next()) |entry| {
            entry.value.deinit();
        }
        self.nodes.deinit();
    }
};

pub const DominanceNode = struct {
    id: u32,
    children: std.ArrayList(*DominanceNode),

    const Self = @This();

    pub fn deinit(self: Self) void {
        self.children.deinit();
    }

    pub fn init(allocator: std.mem.Allocator, id: u32) Self {
        return Self{
            .id = id,
            .children = std.ArrayList(*DominanceNode).init(allocator),
        };
    }
};

pub fn computeDominanceTree(allocator: std.mem.Allocator, graph: *const cfgir.ControlFlowGraph) !DominanceTree {
    // we have to use var here , so we can deinit the set
    // the following algorithm does not modify the set.
    var set = try computeDominanceSet(allocator, graph);
    defer set.deinit();
    // First create the nodes
    var tree_nodes = std.AutoHashMap(u32, *DominanceNode).init(allocator);
    var it = set.sets.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const node = try allocator.create(DominanceNode);
        node.* = DominanceNode.init(allocator, key);
        try tree_nodes.put(key, node);
    }

    // Then create the edges
    it = set.sets.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        const value = entry.value_ptr.*;
        //find the closest dominator
        var dom_it = value.iterator();
        while (dom_it.next()) |dom| {
            const dom_id = dom.*;
            if (dom_id == key) {
                continue;
            }
            const dom_dom = set.sets.get(dom_id).?;
            // Check if dom_dom is dominated by all other dominators
            var dom_it2 = value.iterator();
            var is_idom = true;
            while (dom_it2.next()) |dom2| {
                const dom_id2 = dom2.*;
                if (dom_id2 == key) {
                    continue;
                }
                if (!dom_dom.contains(dom_id2)) {
                    is_idom = false;
                    break;
                }
            }
            if (is_idom) {
                // Add edge from dom_id to key
                var dom_node = tree_nodes.get(dom_id).?;
                const child = tree_nodes.get(key).?;
                try dom_node.children.append(child);
                try tree_nodes.put(dom_id, dom_node);
            }
        }
    }
    return DominanceTree{
        .nodes = tree_nodes,
        .root = tree_nodes.get(0).?,
    };
}

pub fn computeDominanceSet(allocator: std.mem.Allocator, graph: *const cfgir.ControlFlowGraph) !DominanceSet {
    const rpo = try computeReversePostOrder(allocator, graph);
    defer rpo.deinit();
    var dom_sets = std.AutoHashMap(u32, HashSet(u32)).init(allocator);
    var dom_0 = HashSet(u32).init(allocator);
    try dom_0.add(0);
    try dom_sets.put(0, dom_0);

    for (1..rpo.items.len) |i| {
        const block_id = rpo.items[i];
        var dom = HashSet(u32).init(allocator);
        var it = graph.blocks.keyIterator();
        while (it.next()) |entry| {
            try dom.add(entry.*);
        }
        try dom_sets.put(block_id, dom);
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (1..rpo.items.len) |i| {
            const block_id = rpo.items[i];
            var tmp = HashSet(u32).init(allocator);
            defer tmp.deinit();
            const block = graph.blocks.get(block_id).?;

            var block_idoms = dom_sets.get(block_id).?;
            switch (block.*) {
                cfgir.BlockTag.Decision => {
                    try predDomIntersec(&block.*.Decision.predecessors, dom_sets, &tmp);
                },
                cfgir.BlockTag.Sequential => {
                    try predDomIntersec(&block.*.Sequential.predecessors, dom_sets, &tmp);
                },
            }
            try tmp.add(block_id);
            if (!isSame(block_idoms, tmp)) {
                changed = true;
                try setValues(tmp, &block_idoms);
                try dom_sets.put(block_id, block_idoms);
            }
        }
    }

    return DominanceSet{ .sets = dom_sets };
}

fn setValues(src: HashSet(u32), dest: *HashSet(u32)) !void {
    dest.clear();
    var it = src.iterator();
    while (it.next()) |item| {
        try dest.add(item.*);
    }
}

fn predDomIntersec(predecessors: *const std.ArrayList(*cfgir.Block), dom_tree: std.AutoHashMap(u32, HashSet(u32)), dest: *HashSet(u32)) !void {
    if (predecessors.items.len == 0) {
        return;
    }
    const firstPredId = getBlockId(predecessors.items[0]);
    const firstPredDom = dom_tree.get(firstPredId).?;
    try setValues(firstPredDom, dest);
    for (1..predecessors.items.len) |i| {
        const predId = getBlockId(predecessors.items[i]);

        const predDom = dom_tree.get(predId).?;
        var it = dest.iterator();
        while (it.next()) |item| {
            if (!predDom.contains(item.*)) {
                _ = dest.remove(item.*);
            }
        }
    }
}

fn getBlockId(block: *cfgir.Block) u32 {
    switch (block.*) {
        cfgir.BlockTag.Decision => return block.*.Decision.id,
        cfgir.BlockTag.Sequential => return block.*.Sequential.id,
    }
}

fn getBlockName(block: *cfgir.Block) []const u8 {
    switch (block.*) {
        cfgir.BlockTag.Decision => return block.*.Decision.name,
        cfgir.BlockTag.Sequential => return block.*.Sequential.name,
    }
}

fn isSame(a: HashSet(u32), b: HashSet(u32)) bool {
    if (a.len() != b.len()) {
        return false;
    }
    var it = a.iterator();
    while (it.next()) |item| {
        if (!b.contains(item.*)) {
            return false;
        }
    }
    return true;
}

fn computeReversePostOrder(allocator: std.mem.Allocator, graph: *const cfgir.ControlFlowGraph) !std.ArrayList(u32) {
    var visited = HashSet(u32).init(allocator);
    defer visited.deinit();
    var post_order = std.ArrayList(u32).init(allocator);
    defer post_order.deinit();
    try dfs(graph.entry, &visited, &post_order);
    // Reverse the post order
    var reversed = std.ArrayList(u32).init(allocator);
    for (0..post_order.items.len) |i| {
        try reversed.append(post_order.items[post_order.items.len - i - 1]);
    }
    return reversed;
}

fn dfs(block: *cfgir.Block, visited: *HashSet(u32), post_order: *std.ArrayList(u32)) !void {
    if (visited.contains(getBlockId(block))) {
        return;
    }
    switch (block.*) {
        cfgir.BlockTag.Decision => {
            try visited.add(block.*.Decision.id);
            if (block.*.Decision.then_block != null) {
                try dfs(block.*.Decision.then_block.?, visited, post_order);
            }
            if (block.*.Decision.else_block != null) {
                try dfs(block.*.Decision.else_block.?, visited, post_order);
            }
            try post_order.append(block.*.Decision.id);
        },
        cfgir.BlockTag.Sequential => {
            try visited.add(block.*.Sequential.id);
            if (block.*.Sequential.successor != null) {
                try dfs(block.*.Sequential.successor.?, visited, post_order);
            }
            try post_order.append(block.*.Sequential.id);
        },
    }
}

pub fn print_dom_tree(tree: DominanceTree) void {
    var it = tree.nodes.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr;
        const value = entry.value_ptr;
        std.debug.print("Block {}: ", .{key.*});
        for (value.*.*.children.items) |child| {
            std.debug.print("{} ", .{child.*.id});
        }
        std.debug.print("\n", .{});
    }
}
pub fn print_dom_set(tree: DominanceSet) void {
    var it = tree.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr;
        const value = entry.value_ptr.*;
        std.debug.print("Block {}: ", .{key.*});
        var it2 = value.iterator();
        while (it2.next()) |item| {
            std.debug.print("{} ", .{item.*});
        }
        std.debug.print("\n", .{});
    }
}

const ast = @import("../ast/ast.zig");
const testing = std.testing;
test "for " {
    // for a in b:
    //    for x in y:
    //       if awrawr:
    var dummyExpr = ast.Expr{ .ident = "dummy" };
    var arenaAllocator = std.heap.ArenaAllocator.init(testing.allocator);
    defer arenaAllocator.deinit();
    const allocator = arenaAllocator.allocator();
    var statements = std.ArrayList(ast.Statement).init(allocator);
    var outerForBody = std.ArrayList(ast.Statement).init(allocator);
    var innerForBody = std.ArrayList(ast.Statement).init(allocator);
    var innerBodyStatements = std.ArrayList(ast.Statement).init(allocator);
    var innerBodyExpr = ast.Expr{ .ident = "awrawr" };
    try innerBodyStatements.append(ast.Statement{ .simple_statement = ast.SimpleStatement{ .expr = &innerBodyExpr } });
    var innerForBodyConditionExpr = ast.Expr{ .ident = "y" };
    try innerForBody.append(ast.Statement{ .if_statement = ast.IfStatement{
        .condition = &innerForBodyConditionExpr,
        .body = ast.Suite{ .statements = innerBodyStatements },
    } });
    var outerForBodyIter = ast.Expr{ .ident = "b" };
    try outerForBody.append(ast.Statement{ .for_in_statement = ast.ForInStatement{
        .var_name = "x",
        .iterable = &outerForBodyIter,
        .body = ast.Suite{
            .statements = innerForBody,
        },
    } });
    const outerFor = ast.ForInStatement{ .var_name = "a", .iterable = &dummyExpr, .body = ast.Suite{ .statements = outerForBody } };

    try statements.append(ast.Statement{ .for_in_statement = outerFor });

    const cfg = try cfgir.astStatementsToCFG(allocator, statements.items, "abc");
    //try printCfg(cfg);
    const domTree = try computeDominanceSet(allocator, &cfg);
    print_dom_set(domTree);
}
