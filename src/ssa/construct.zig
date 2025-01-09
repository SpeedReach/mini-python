const cfgir = @import("../cfgir/cfgir.zig");
const ast = @import("../ast/ast.zig");
const CfgIR = cfgir.Program;
const CfgBlock = cfgir.Block;
const CfgNormalBlock = cfgir.NormalBlock;
const CfgDecisionBlock = cfgir.DecisionBlock;

const ssa = @import("./ssa.zig");
const math = std.math;
const std = @import("std");
const dom = @import("./dom_frontiers.zig");
const VariableCounter = @import("./variable_counter.zig").VariableCounter;

const HashSet = @import("../ds/set.zig").HashSet;
const Queue = @import("../ds/queue.zig").Queue;

const Error = error{ Todo, Unexpected };

pub const AnnotatedCfg = struct {
    name: []const u8,
    args: std.ArrayList([]const u8),
    blocks: std.AutoHashMap(u32, *AnnotatedBlock),
    dom_tree: dom.DominanceTree,
    entry: u32,
    exit: u32,

    pub fn deinit(self: *AnnotatedCfg, allocator: std.mem.Allocator) void {
        self.args.deinit();
        var it = self.blocks.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.value_ptr.*);
        }
        self.blocks.deinit();
    }
};

pub const AnnotatedBlockTag = enum { Sequential, Decision };

pub const AnnotatedBlock = union(AnnotatedBlockTag) { Sequential: AnnotatedNormalBlock, Decision: AnnotatedDecisionBlock };

pub const AnnotatedNormalBlock = struct {
    inner: *CfgNormalBlock,
    used_vars: std.StringHashMap(void),
    assigned_vars: std.StringHashMap(void),
    phis: std.StringHashMap(std.ArrayList(ssa.PhiValue)),
};

pub const AnnotatedDecisionBlock = struct {
    inner: *CfgDecisionBlock,
    used_vars: std.StringHashMap(void),
    phis: std.StringHashMap(std.ArrayList(ssa.PhiValue)),
};

const AnnotatedContext = struct {
    global_vars: std.StringHashMap(void),
    const_strings: std.StringHashMap(void),
    functions: std.StringHashMap(AnnotatedCfg),
    main: AnnotatedCfg,

    const Self = @This();
    pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
        self.global_vars.deinit();
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(allocator);
        }
    }
};

pub const SSAConstructor = struct {
    allocator: std.mem.Allocator,
    context: AnnotatedContext,

    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, context: AnnotatedContext) SSAConstructor {
        return SSAConstructor{
            .allocator = allocator,
            .context = context,
        };
    }

    pub fn deinit(self: Self) void {
        self.counter.deinit();
    }

    pub fn buildSSA(self: Self) !ssa.Program {
        const main_context = try self.buildCfg(&self.context.main);
        var functions = std.StringHashMap(ssa.FunctionContext).init(self.allocator);
        var it = self.context.functions.iterator();
        while (it.next()) |entry| {
            try functions.put(entry.key_ptr.*, try self.buildCfg(entry.value_ptr));
        }
        return ssa.Program{
            .const_strings = self.context.const_strings,
            .functions = functions,
            .global_vars = self.context.global_vars,
            .main = main_context,
        };
    }

    fn buildCfg(self: Self, cfg: *const AnnotatedCfg) !ssa.FunctionContext {
        var ssa_context = ssa.FunctionContext{
            .name = cfg.name,
            .blocks = std.AutoHashMap(u32, *ssa.Block).init(self.allocator),
        };

        const dom_tree = cfg.dom_tree;
        const dom_node = dom_tree.root;
        var var_counter = VariableCounter.init(self.allocator, &self.context.global_vars);
        defer var_counter.deinit();

        try self.dfsBuildBlock(&cfg.args, &cfg.blocks, &ssa_context.blocks, dom_node, &var_counter);
        try setPhiValuesToInsts(&cfg.blocks, &ssa_context.blocks);
        return ssa_context;
    }

    fn setPhiValuesToInsts(anns: *const std.AutoHashMap(u32, *AnnotatedBlock), ssas: *std.AutoHashMap(u32, *ssa.Block)) !void {
        var it = ssas.iterator();
        while (it.next()) |entry| {
            const block_id = entry.key_ptr.*;
            const ann_block = anns.get(block_id).?;
            var instructions: *std.ArrayList(ssa.Instruction) = undefined;
            var phis: *std.StringHashMap(std.ArrayList(ssa.PhiValue)) = undefined;
            switch (entry.value_ptr.*.*) {
                .Decision => {
                    phis = &ann_block.*.Decision.phis;
                    instructions = &entry.value_ptr.*.*.Decision.instructions;
                },
                .Sequential => {
                    phis = &ann_block.*.Sequential.phis;
                    instructions = &entry.value_ptr.*.*.Sequential.instructions;
                },
            }
            for (0..instructions.items.len) |i| {
                const inst = instructions.items[i];
                if (inst != .Assignment) {
                    break;
                }
                if (inst.Assignment.rhs != .Phi) {
                    break;
                }

                for (phis.get(inst.Assignment.variable.base).?.items) |phi| {
                    try instructions.items[i].Assignment.rhs.Phi.values.append(phi);
                }
            }
        }
    }

    fn dfsBuildBlock(
        self: Self,
        args: ?*const std.ArrayList([]const u8),
        blocks: *const std.AutoHashMap(u32, *AnnotatedBlock),
        dest: *std.AutoHashMap(u32, *ssa.Block),
        dom_node: *const dom.DominanceNode,
        var_counter: *VariableCounter,
    ) !void {
        const block = blocks.get(dom_node.id).?;

        //After leaving the block, we need to pop the variables from the counter
        //So dominator siblings can use the same variable names
        var var_on_entry = std.StringHashMap(ssa.Variable).init(self.allocator);
        //We need to keep track of variables that are assigned and updated in the block, so we can update its successors phi values
        var new_vars = std.StringHashMap(void).init(self.allocator);
        defer new_vars.deinit();
        defer var_on_entry.deinit();
        if (block.* == .Sequential) {
            var it = block.*.Sequential.assigned_vars.keyIterator();
            while (it.next()) |name_ptr| {
                const name = name_ptr.*;
                try new_vars.put(name, void{});
                const latest_version = var_counter.getLatest(name);
                if (latest_version != null) {
                    try var_on_entry.put(name, latest_version.?);
                }
            }
        }
        var it = if (block.* == .Sequential) block.*.Sequential.phis.keyIterator() else block.*.Decision.phis.keyIterator();
        while (it.next()) |name_ptr| {
            const name = name_ptr.*;
            try new_vars.put(name, void{});
            const latest_version = var_counter.getLatest(name);
            if (latest_version != null) {
                try var_on_entry.put(name, latest_version.?);
            }
        }

        const entry_block = try self.buildBlock(self.allocator, args, block.*, var_counter);

        try self.setSuccessorsPhiVals(blocks, dom_node.id, new_vars, var_counter);

        try dest.put(dom_node.id, entry_block);
        for (dom_node.children.items) |child| {
            try self.dfsBuildBlock(null, blocks, dest, child, var_counter);
        }

        var var_it = var_on_entry.iterator();
        while (var_it.next()) |entry| {
            const name = entry.key_ptr.*;
            const version = entry.value_ptr.*;
            try var_counter.popUntil(name, version.version);
        }
    }

    fn getBlockName(block: *AnnotatedBlock) []const u8 {
        switch (block.*) {
            .Decision => return block.*.Decision.inner.*.name,
            .Sequential => return block.*.Sequential.inner.*.name,
        }
    }
    fn setPhiValues(block: *AnnotatedBlock, preccedor_id: u32, new_vars: std.StringHashMap(void), counter: *const VariableCounter) !void {
        switch (block.*) {
            .Decision => {
                var it = block.*.Decision.phis.keyIterator();
                while (it.next()) |phi| {
                    if (!new_vars.contains(phi.*)) {
                        continue;
                    }
                    const latest = counter.getLatest(phi.*);
                    if (latest != null) {
                        try block.*.Decision.phis.getPtr(phi.*).?.*.append(ssa.PhiValue{ .block = preccedor_id, .value = ssa.Value{
                            .Var = ssa.Variable{
                                .version = latest.?.version,
                                .base = phi.*,
                            },
                        } });
                    }
                }
            },
            .Sequential => {
                var it = block.*.Sequential.phis.keyIterator();
                while (it.next()) |phi| {
                    if (!new_vars.contains(phi.*)) {
                        continue;
                    }
                    const latest = counter.getLatest(phi.*);
                    if (latest != null) {
                        try block.*.Sequential.phis.getPtr(phi.*).?.*.append(ssa.PhiValue{ .block = preccedor_id, .value = ssa.Value{
                            .Var = ssa.Variable{
                                .version = latest.?.version,
                                .base = phi.*,
                            },
                        } });
                    }
                }
            },
        }
    }

    fn getAnnotatedId(block: *AnnotatedBlock) u32 {
        switch (block.*) {
            .Decision => return block.*.Decision.inner.*.id,
            .Sequential => return block.*.Sequential.inner.*.id,
        }
    }

    fn setSuccessorsPhiVals(self: Self, blocks: *const std.AutoHashMap(u32, *AnnotatedBlock), start: u32, new_vars: std.StringHashMap(void), counter: *const VariableCounter) !void {
        var walked = HashSet(u32).init(self.allocator);
        var queue = Queue(u32).init(self.allocator);
        defer walked.deinit();
        defer queue.deinit();
        try queue.enqueue(start);

        while (queue.dequeue()) |block_id| {
            if (walked.contains(block_id)) {
                continue;
            }
            try walked.add(block_id);

            const block = blocks.get(block_id).?;
            try setPhiValues(block, start, new_vars, counter);
            switch (block.*) {
                .Decision => |des| {
                    const thenId = getBlockId(des.inner.then_block.?);
                    const elseId = getBlockId(des.inner.else_block.?);
                    if (!walked.contains(thenId)) {
                        try queue.enqueue(thenId);
                    }
                    if (!walked.contains(elseId)) {
                        try queue.enqueue(elseId);
                    }
                },
                .Sequential => |seq| {
                    const succ = seq.inner.successor;
                    if (succ == null) {
                        continue;
                    }
                    const succ_id = getBlockId(succ.?);
                    if (!walked.contains(succ_id)) {
                        try queue.enqueue(succ_id);
                    }
                },
            }
        }
    }

    fn buildBlock(
        self: Self,
        allocator: std.mem.Allocator,
        args: ?*const std.ArrayList([]const u8),
        block: AnnotatedBlock,
        counter: *VariableCounter,
    ) !*ssa.Block {
        const ssa_block = try allocator.create(ssa.Block);
        switch (block) {
            .Decision => |decision| {
                var instructions = std.ArrayList(ssa.Instruction).init(allocator);
                try addPhiDeclares(allocator, decision.phis, &instructions, counter);
                if (args != null) {
                    var i: u8 = 0;
                    for (args.?.items) |arg| {
                        try instructions.append(ssa.Instruction{ .Assignment = ssa.Assignment{ .variable = try counter.add(arg), .rhs = ssa.AssignValue{
                            .FunctionArg = i,
                        } } });
                        i += 1;
                    }
                }
                const condition_val = try self.handleExpr(&decision.inner.condition, &instructions, counter);
                ssa_block.* = ssa.Block{ .Decision = ssa.DecisionBlock{
                    .id = block.Decision.inner.*.id,
                    .name = block.Decision.inner.*.name,
                    .condition = condition_val,
                    .else_block = getBlockId(block.Decision.inner.*.else_block.?),
                    .then_block = getBlockId(block.Decision.inner.*.then_block.?),
                    .instructions = instructions,
                    .predecessors = try getBlocksId(allocator, &block.Decision.inner.*.predecessors),
                } };

                return ssa_block;
            },
            .Sequential => |sequential| {
                var instructions = std.ArrayList(ssa.Instruction).init(allocator);

                try addPhiDeclares(allocator, sequential.phis, &instructions, counter);
                if (args != null) {
                    var i: u8 = 0;
                    for (args.?.items) |arg| {
                        try instructions.append(ssa.Instruction{ .Assignment = ssa.Assignment{
                            .variable = try counter.add(arg),
                            .rhs = ssa.AssignValue{
                                .FunctionArg = i,
                            },
                        } });
                        i += 1;
                    }
                }

                for (sequential.inner.*.statements.items) |stmt| {
                    try self.handleStatement(stmt, &instructions, counter);
                }

                if (sequential.inner.*.successor == null) {
                    ssa_block.* = ssa.Block{ .Sequential = ssa.NormalBlock{
                        .name = block.Sequential.inner.*.name,
                        .id = block.Sequential.inner.*.id,
                        .instructions = instructions,
                        .predecessors = try getBlocksId(allocator, &block.Sequential.inner.*.predecessors),
                        .successor = std.math.maxInt(u32),
                    } };
                    return ssa_block;
                }
                const successor = getBlockId(sequential.inner.*.successor.?);
                ssa_block.* = ssa.Block{ .Sequential = ssa.NormalBlock{
                    .name = block.Sequential.inner.*.name,
                    .id = block.Sequential.inner.*.id,
                    .instructions = instructions,
                    .predecessors = try getBlocksId(allocator, &block.Sequential.inner.*.predecessors),
                    .successor = successor,
                } };

                return ssa_block;
            },
        }
    }

    fn handleStatement(self: Self, statement: ast.SimpleStatement, dest: *std.ArrayList(ssa.Instruction), vars: *VariableCounter) !void {
        switch (statement) {
            .assign => |assign| {
                const is_global_var = self.context.global_vars.contains(assign.lhs);
                const rhs = try self.handleExpr(assign.rhs, dest, vars);
                if (is_global_var) {
                    const inst = ssa.Instruction{ .Store = ssa.StoreInstruction{
                        .value = rhs,
                        .name = assign.lhs,
                    } };
                    try dest.append(inst);
                } else {
                    const lhs = try vars.add(assign.lhs);
                    const inst = ssa.Instruction{ .Assignment = ssa.Assignment{
                        .variable = lhs,
                        .rhs = ssa.AssignValue{
                            .Value = rhs,
                        },
                    } };
                    try dest.append(inst);
                }
            },
            .assign_list => |assign_list| {
                try self.handleListAssign(&assign_list, dest, vars);
            },
            .@"return" => |ret| {
                const value = try self.handleExpr(ret, dest, vars);
                const inst = ssa.Instruction{ .Return = value };
                try dest.append(inst);
            },
            .expr => |expr| {
                const value = try self.handleExpr(expr, dest, vars);
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{
                    .variable = try vars.add("tmp"),
                    .rhs = ssa.AssignValue{ .Value = value },
                } };
                try dest.append(inst);
            },
            .print => |print| {
                const value = try self.handleExpr(print.value, dest, vars);
                const inst = ssa.Instruction{ .Print = value };
                try dest.append(inst);
            },
        }
    }

    /// a = [[3, 4]]
    /// a[0][1] = 5
    /// =>
    /// tmp1 = [3,4]
    /// a_1 = [tmp1]
    ///
    /// tmp2 = a[0]
    /// tmp3 = (tmp2, 1, 5)
    /// a_2 = (a_1, 0, tmp3)
    fn handleListAssign(self: Self, list_write: *const ast.ListWrite, dest: *std.ArrayList(ssa.Instruction), vars: *VariableCounter) !void {
        const array_root = attemptFindArrayRoot(list_write.lhs.*);
        if (array_root == null) {
            return;
        }
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};

        const allocator = gpa.allocator();
        const ListAccess = struct {
            idx: ssa.Value,
            base: []const u8,
        };

        var access_lists = std.ArrayList(ListAccess).init(allocator);
        defer access_lists.deinit();

        const is_global_var = self.context.global_vars.contains(array_root.?);
        var base: []const u8 = undefined;
        var first_array: ssa.Variable = undefined;
        if (is_global_var) {
            base = "tmp";
            first_array = try vars.add(base);
            const load_inst = ssa.Instruction{ .Assignment = ssa.Assignment{
                .variable = first_array,
                .rhs = ssa.AssignValue{ .Load = array_root.? },
            } };
            try dest.append(load_inst);
        } else {
            base = array_root.?;
            first_array = try vars.getLatestOrAdd(base);
        }

        try access_lists.append(ListAccess{
            .idx = try self.handleExpr(list_write.*.idx, dest, vars),
            .base = if (list_write.lhs.* == .ident) base else "tmp",
        });

        var expr: *const ast.Expr = list_write.lhs;
        while (expr.* == .list_access) {
            const idx = try self.handleExpr(expr.*.list_access.idx, dest, vars);

            switch (expr.*.list_access.list.*) {
                ast.ExprTag.list_access => {
                    try access_lists.append(ListAccess{ .idx = idx, .base = "tmp" });
                    expr = expr.*.list_access.list;
                },
                ast.ExprTag.ident => {
                    try access_lists.append(ListAccess{ .idx = idx, .base = base });
                    break;
                },
                else => {
                    return Error.Unexpected;
                },
            }
        }

        var array = first_array;
        var new_vars = std.ArrayList(ssa.Variable).init(allocator);
        for (0..access_lists.items.len - 1) |i| {
            const ri = access_lists.items.len - i - 1;
            const access = access_lists.items[ri];
            const idx = access.idx;
            const new_var = try vars.add("tmp");
            const inst = ssa.Instruction{ .Assignment = ssa.Assignment{
                .variable = new_var,
                .rhs = ssa.AssignValue{ .ArrayRead = ssa.ArrayReadExpr{
                    .array = array,
                    .idx = idx,
                } },
            } };
            try dest.append(inst);

            try new_vars.append(array);
            array = new_var;
        }

        const last_access = access_lists.items[0];
        const idx = last_access.idx;
        const new_value = try self.handleExpr(list_write.rhs, dest, vars);
        const new_dest_t = if (access_lists.items.len == 1) try vars.add(base) else try vars.add("tmp");
        const inst = ssa.Instruction{ .Assignment = ssa.Assignment{
            .rhs = ssa.AssignValue{ .ArrayWrite = ssa.ArrayWriteExpr{
                .array = array,
                .idx = idx,
                .root = "",
                .value = new_value,
            } },
            .variable = new_dest_t,
        } };
        try dest.append(inst);

        var new_dest = new_dest_t;
        const len = new_vars.items.len;
        for (0..new_vars.items.len) |i| {
            const a = new_vars.items[len - 1 - i];
            const b = access_lists.items[i + 1];
            const new_dest_tmp = try vars.add(a.base);
            const inst1 = ssa.Instruction{ .Assignment = ssa.Assignment{
                .variable = new_dest_tmp,
                .rhs = ssa.AssignValue{ .ArrayWrite = ssa.ArrayWriteExpr{
                    .array = a,
                    .idx = b.idx,
                    .root = "",
                    .value = ssa.Value{ .Var = new_dest },
                } },
            } };
            try dest.append(inst1);
            new_dest = new_dest_tmp;
        }
        if (is_global_var) {
            const store_inst = ssa.Instruction{ .Store = ssa.StoreInstruction{
                .name = array_root.?,
                .value = ssa.Value{ .Var = new_dest },
            } };
            try dest.append(store_inst);
        }
    }

    fn addPhiDeclares(allocator: std.mem.Allocator, phis: std.StringHashMap(std.ArrayList(ssa.PhiValue)), dest: *std.ArrayList(ssa.Instruction), vars: *VariableCounter) !void {
        var it = phis.keyIterator();
        while (it.next()) |phi| {
            const name = try vars.add(phi.*);
            const inst = ssa.Instruction{
                .Assignment = ssa.Assignment{ .variable = name, .rhs = ssa.AssignValue{ .Phi = ssa.PhiValues{
                    .base = phi.*,
                    .values = std.ArrayList(ssa.PhiValue).init(allocator),
                } } },
            };
            try dest.append(inst);
        }
    }

    fn handleExpr(self: Self, expr: *ast.Expr, dest: *std.ArrayList(ssa.Instruction), vars: *VariableCounter) !ssa.Value {
        switch (expr.*) {
            ast.ExprTag.bin_op => {
                const lhs = try self.handleExpr(expr.*.bin_op.lhs, dest, vars);
                const rhs = try self.handleExpr(expr.*.bin_op.rhs, dest, vars);
                const tmp = try vars.add("tmp");
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{
                    .variable = tmp,
                    .rhs = ssa.AssignValue{ .BinOp = ssa.BinOpExpr{
                        .lhs = lhs,
                        .rhs = rhs,
                        .op = expr.*.bin_op.op,
                    } },
                } };
                try dest.append(inst);
                return ssa.Value{ .Var = tmp };
            },
            ast.ExprTag.ident => {
                const is_global_var = self.context.global_vars.contains(expr.*.ident);
                if (is_global_var) {
                    const tmp = try vars.add("tmp");
                    const load_inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .variable = tmp, .rhs = ssa.AssignValue{
                        .Load = expr.*.ident,
                    } } };
                    try dest.append(load_inst);
                    return ssa.Value{ .Var = tmp };
                } else {
                    return ssa.Value{ .Var = try vars.getLatestOrAdd(expr.*.ident) };
                }
            },
            ast.ExprTag.@"const" => {
                return ssa.Value{ .Const = toSSAConst(expr.*.@"const") };
            },
            ast.ExprTag.function_call => {
                var args = std.ArrayList(ssa.Value).init(self.allocator);
                for (expr.*.function_call.args.items) |arg| {
                    try args.append(try self.handleExpr(arg, dest, vars));
                }
                const tmp = try vars.add("tmp");
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .variable = tmp, .rhs = ssa.AssignValue{ .FunctionCall = ssa.FunctionCallExpr{
                    .name = expr.function_call.name,
                    .args = args,
                } } } };
                try dest.append(inst);
                return ssa.Value{ .Var = tmp };
            },
            ast.ExprTag.list_access => {
                const list = try self.handleExpr(expr.*.list_access.list, dest, vars);
                if (list != .Var) {
                    return Error.Unexpected;
                }
                const idx = try self.handleExpr(expr.*.list_access.idx, dest, vars);
                const tmp = try vars.add("tmp");
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .variable = tmp, .rhs = ssa.AssignValue{ .ArrayRead = ssa.ArrayReadExpr{
                    .array = list.Var,
                    .idx = idx,
                } } } };
                try dest.append(inst);
                return ssa.Value{ .Var = tmp };
            },
            ast.ExprTag.list_declare => {
                var values = std.ArrayList(ssa.Value).init(self.allocator);
                for (expr.*.list_declare.values.items) |item| {
                    try values.append(try self.handleExpr(item, dest, vars));
                }
                const tmp = try vars.add("tmp");
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .variable = tmp, .rhs = ssa.AssignValue{
                    .ListValue = values,
                } } };
                try dest.append(inst);
                return ssa.Value{ .Var = tmp };
            },
            ast.ExprTag.not_expr => {
                const inner = try self.handleExpr(expr.*.not_expr, dest, vars);
                const tmp = try vars.add("tmp");
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .variable = tmp, .rhs = ssa.AssignValue{
                    .Not = inner,
                } } };
                try dest.append(inst);
                return ssa.Value{ .Var = tmp };
            },
            ast.ExprTag.unary_expr => {
                const inner = try self.handleExpr(expr.*.unary_expr, dest, vars);
                const tmp = try vars.add("tmp");
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .variable = tmp, .rhs = ssa.AssignValue{
                    .Unary = inner,
                } } };
                try dest.append(inst);
                return ssa.Value{ .Var = tmp };
            },
        }
    }
};

pub fn attemptFindArrayRoot(expr: ast.Expr) ?[]const u8 {
    switch (expr) {
        ast.ExprTag.ident => return expr.ident,
        ast.ExprTag.list_access => return attemptFindArrayRoot(expr.list_access.list.*),
        else => return null,
    }
}

fn getBlockId(block: *const CfgBlock) u32 {
    switch (block.*) {
        cfgir.BlockTag.Decision => return block.*.Decision.id,
        cfgir.BlockTag.Sequential => return block.*.Sequential.id,
    }
}

fn getBlocksId(allocator: std.mem.Allocator, blocks: *std.ArrayList(*CfgBlock)) !std.ArrayList(u32) {
    var ids = std.ArrayList(u32).init(allocator);
    for (blocks.items) |block| {
        try ids.append(getBlockId(block));
    }
    return ids;
}

pub fn constructSSA(allocator: std.mem.Allocator, cfgIR: *const CfgIR) !ssa.Program {
    var global_vars = std.StringHashMap(void).init(allocator);
    var const_strings = std.StringHashMap(void).init(allocator);
    try identifyGlobalContext(cfgIR, &global_vars);

    var functions = std.StringHashMap(AnnotatedCfg).init(allocator);
    var it = cfgIR.functions.iterator();
    while (it.next()) |entry| {
        const args = try entry.value_ptr.*.args.clone();
        try functions.put(entry.key_ptr.*, try annotateCfg(allocator, &global_vars, &const_strings, args, entry.value_ptr));
    }
    const main = try annotateCfg(allocator, &global_vars, &const_strings, std.ArrayList([]const u8).init(allocator), &cfgIR.main);
    const context = AnnotatedContext{
        .global_vars = global_vars,
        .const_strings = const_strings,
        .functions = functions,
        .main = main,
    };
    var constructor = SSAConstructor.init(allocator, context);
    return try constructor.buildSSA();
}

fn annotateCfg(allocator: std.mem.Allocator, global_vars: *std.StringHashMap(void), const_strings: *std.StringHashMap(void), args: std.ArrayList([]const u8), cfg: *const cfgir.ControlFlowGraph) !AnnotatedCfg {
    var blocks = std.AutoHashMap(u32, *AnnotatedBlock).init(allocator);
    var it = cfg.blocks.valueIterator();
    while (it.next()) |item| {
        var used_vars = std.StringHashMap(void).init(allocator);
        try identifyUsedVars(item.*, &used_vars, const_strings);
        defer used_vars.deinit();
        switch (item.*.*) {
            cfgir.BlockTag.Decision => {
                const block = try allocator.create(AnnotatedBlock);
                block.* = AnnotatedBlock{
                    .Decision = AnnotatedDecisionBlock{
                        .inner = &item.*.*.Decision,
                        .used_vars = try used_vars.clone(),
                        .phis = std.StringHashMap(std.ArrayList(ssa.PhiValue)).init(allocator),
                    },
                };
                try blocks.put(item.*.*.Decision.id, block);
            },
            cfgir.BlockTag.Sequential => {
                var assigned_vars = std.StringHashMap(void).init(allocator);
                defer assigned_vars.deinit();
                for (args.items) |arg| {
                    try assigned_vars.put(arg, void{});
                }
                try identifyAssignedVars(item.*, &assigned_vars);
                const block = try allocator.create(AnnotatedBlock);
                block.* = AnnotatedBlock{
                    .Sequential = AnnotatedNormalBlock{
                        .inner = &item.*.*.Sequential,
                        .used_vars = try used_vars.clone(),
                        .assigned_vars = try assigned_vars.clone(),
                        .phis = std.StringHashMap(std.ArrayList(ssa.PhiValue)).init(allocator),
                    },
                };
                try blocks.put(item.*.*.Sequential.id, block);
            },
        }
    }
    const dom_tree = try dom.computeDominanceTree(allocator, cfg);
    const dom_frontiers = try dom.computeDominaceFrontiers(allocator, dom_tree, cfg.*);
    var annotated = AnnotatedCfg{
        .name = cfg.name,
        .blocks = blocks,
        .entry = 0,
        .exit = math.maxInt(u32),
        .dom_tree = dom_tree,
        .args = args,
    };
    try insertPhis(global_vars, &annotated, dom_frontiers);
    return annotated;
}

fn insertPhis(global_var: *const std.StringHashMap(void), cfg: *const AnnotatedCfg, _: dom.DominaceFrontiers) !void {
    var it = cfg.blocks.valueIterator();
    while (it.next()) |block| {
        switch (block.*.*) {
            AnnotatedBlockTag.Decision => {
                var var_it = block.*.*.Decision.used_vars.keyIterator();
                while (var_it.next()) |used_var| {
                    if (global_var.contains(used_var.*)) {
                        continue;
                    }
                    const phi_values = std.ArrayList(ssa.PhiValue).init(block.*.*.Decision.phis.allocator);
                    try block.*.*.Decision.phis.put(used_var.*, phi_values);
                }
            },
            AnnotatedBlockTag.Sequential => {
                var var_it = block.*.*.Sequential.used_vars.keyIterator();
                while (var_it.next()) |used_var| {
                    if (global_var.contains(used_var.*)) {
                        continue;
                    }
                    const phi_values = std.ArrayList(ssa.PhiValue).init(block.*.*.Sequential.phis.allocator);
                    try block.*.*.Sequential.phis.put(used_var.*, phi_values);
                }
            },
        }
    }
}

fn identifyGlobalContext(cfg: *const CfgIR, global_vars: *std.StringHashMap(void)) !void {
    var it = cfg.main.blocks.valueIterator();
    while (it.next()) |block| {
        try identifyAssignedVars(block.*, global_vars);
    }
    var w = cfg.main.created_vars.keyIterator();
    while (w.next()) |k| {
        _ = global_vars.remove(k.*);
    }
}

fn identifyUsedVars(block: *CfgBlock, used_vars: *std.StringHashMap(void), const_strings: *std.StringHashMap(void)) !void {
    switch (block.*) {
        cfgir.BlockTag.Decision => {
            try identifyExprUsedVars(&block.*.Decision.condition, used_vars, const_strings);
        },
        cfgir.BlockTag.Sequential => {
            for (block.*.Sequential.statements.items) |stmt| {
                switch (stmt) {
                    .assign => {
                        try identifyExprUsedVars(stmt.assign.rhs, used_vars, const_strings);
                    },
                    .assign_list => {
                        try identifyExprUsedVars(stmt.assign_list.idx, used_vars, const_strings);
                        try identifyExprUsedVars(stmt.assign_list.lhs, used_vars, const_strings);
                        try identifyExprUsedVars(stmt.assign_list.rhs, used_vars, const_strings);
                    },
                    .@"return" => {
                        try identifyExprUsedVars(stmt.@"return", used_vars, const_strings);
                    },
                    .expr => {
                        try identifyExprUsedVars(stmt.expr, used_vars, const_strings);
                    },
                    .print => {
                        try identifyExprUsedVars(stmt.print.value, used_vars, const_strings);
                    },
                }
            }
        },
    }
}

fn identifyExprUsedVars(expr: *ast.Expr, used_vars: *std.StringHashMap(void), const_strings: *std.StringHashMap(void)) !void {
    switch (expr.*) {
        ast.ExprTag.ident => {
            try used_vars.put(expr.*.ident, void{});
        },
        ast.ExprTag.bin_op => {
            try identifyExprUsedVars(expr.*.bin_op.lhs, used_vars, const_strings);
            try identifyExprUsedVars(expr.*.bin_op.rhs, used_vars, const_strings);
        },
        ast.ExprTag.function_call => {
            for (expr.*.function_call.args.items) |arg| {
                try identifyExprUsedVars(arg, used_vars, const_strings);
            }
        },
        ast.ExprTag.list_access => {
            try identifyExprUsedVars(expr.*.list_access.list, used_vars, const_strings);
            try identifyExprUsedVars(expr.*.list_access.idx, used_vars, const_strings);
        },
        ast.ExprTag.list_declare => {
            for (expr.*.list_declare.values.items) |value| {
                try identifyExprUsedVars(value, used_vars, const_strings);
            }
        },
        ast.ExprTag.not_expr => {
            try identifyExprUsedVars(expr.*.not_expr, used_vars, const_strings);
        },
        ast.ExprTag.unary_expr => {
            try identifyExprUsedVars(expr.*.unary_expr, used_vars, const_strings);
        },
        ast.ExprTag.@"const" => {
            switch (expr.*.@"const") {
                .string => {
                    try const_strings.put(expr.*.@"const".string, void{});
                },
                else => {},
            }
        },
    }
}

fn identifyAssignedVars(block: *CfgBlock, var_set: *std.StringHashMap(void)) !void {
    switch (block.*) {
        cfgir.BlockTag.Decision => {},
        cfgir.BlockTag.Sequential => {
            for (block.*.Sequential.statements.items) |stmt| {
                switch (stmt) {
                    .assign => {
                        try var_set.put(stmt.assign.lhs, void{});
                    },
                    .assign_list => {
                        try identifyListAssignedVars(stmt.assign_list.lhs, var_set);
                    },
                    else => {},
                }
            }
        },
    }
}

fn toSSAConst(csnt: ast.Const) ssa.Const {
    switch (csnt) {
        .int => return ssa.Const{ .int = csnt.int },
        .string => return ssa.Const{ .string = csnt.string },
        .boolean => return ssa.Const{ .boolean = csnt.boolean },
        .none => return ssa.Const{ .none = csnt.none },
    }
}
fn identifyListAssignedVars(list: *ast.Expr, var_set: *std.StringHashMap(void)) !void {
    switch (list.*) {
        .ident => {
            try var_set.put(list.ident, void{});
        },
        .list_access => {
            try identifyListAssignedVars(list.list_access.list, var_set);
        },
        else => {},
    }
}

const parse = @import("../parser/parser.zig");
pub fn compile(allocator: std.mem.Allocator, code: [:0]const u8) !*CfgIR {
    var parser = parse.Parser.init(allocator, code);
    const ast_file = parser.parse() catch |err| {
        return err;
    };
    const w = try cfgir.astToCfgIR(allocator, ast_file);
    return w;
}

test "init" {
    const code =
        \\def add(a, b):
        \\  a = 4
        \\  if (a == 0 or b == 0): 
        \\    return b
        \\  else:
        \\    return add(a - 1, b + 1)
        \\
        \\w = add(1, 2)
        \\
        \\print(w)
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const cfgIR = try compile(allocator, code);
    const ssaConstructor = try SSAConstructor.init(std.heap.page_allocator, cfgIR);
    std.debug.print("main\n", .{});
    printStringSet(&ssaConstructor.global_vars);
    var it = ssaConstructor.functions.iterator();
    while (it.next()) |entry| {
        var b_it = entry.value_ptr.*.blocks.iterator();

        while (b_it.next()) |b_entry| {
            switch (b_entry.value_ptr.*.*) {
                .Sequential => |seq| {
                    std.debug.print("{s} Sequential\n", .{seq.inner.*.name});
                    printStringSet(&seq.used_vars);
                    std.debug.print("assigned_vars\n", .{});
                    printStringSet(&seq.assigned_vars);
                },
                .Decision => |des| {
                    std.debug.print("{s} Decision\n", .{des.inner.*.name});
                    printStringSet(&des.used_vars);
                },
            }
        }
    }
}

fn printStringSet(set: *const std.StringHashMap(void)) void {
    var it = set.keyIterator();
    while (it.next()) |key| {
        std.debug.print("{s}, ", .{key.*});
    }
    std.debug.print("\n", .{});
}
