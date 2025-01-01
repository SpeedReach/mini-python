const cfgir = @import("../cfgir/cfgir.zig");
const ast = @import("../ast/ast.zig");
const CfgIR = cfgir.Program;
const CfgBlock = cfgir.Block;
const CfgNormalBlock = cfgir.NormalBlock;
const CfgDecisionBlock = cfgir.DecisionBlock;

const ssa = @import("./ssa.zig");
const math = std.math;
const std = @import("std");
const dom = @import("./dom_tree.zig");
const VariableCounter = @import("./variable_counter.zig").VariableCounter;

const Error = error{
    Todo,
};

pub const AnnotatedCfg = struct {
    blocks: std.AutoHashMap(u32, *AnnotatedBlock),
    dom_tree: dom.DominanceTree,
    entry: u32,
    exit: u32,
};

pub const AnnotatedBlockTag = enum { Sequential, Decision };

pub const AnnotatedBlock = union(AnnotatedBlockTag) { Sequential: AnnotatedNormalBlock, Decision: AnnotatedDecisionBlock };

pub const AnnotatedNormalBlock = struct {
    inner: *CfgNormalBlock,
    used_vars: std.StringHashMap(void),
    assigned_vars: std.StringHashMap(void),
    phis: std.StringHashMap(void),
};

pub const AnnotatedDecisionBlock = struct {
    inner: *CfgDecisionBlock,
    used_vars: std.StringHashMap(void),
    phis: std.StringHashMap(void),
};

const AnnotatedContext = struct {
    global_vars: std.StringHashMap(void),
    functions: std.StringHashMap(AnnotatedCfg),
    main: AnnotatedCfg,

    const Self = @This();
    pub fn deinit(self: Self) void {
        self.global_vars.deinit();
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
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
            .functions = functions,
            .global_vars = self.context.global_vars,
            .main = main_context,
        };
    }

    fn buildCfg(self: Self, cfg: *const AnnotatedCfg) !ssa.FunctionContext {
        var ssa_context = ssa.FunctionContext{
            .blocks = std.AutoHashMap(u32, *ssa.Block).init(self.allocator),
        };
        const dom_tree = cfg.dom_tree;
        const dom_node = dom_tree.root;
        var var_counter = VariableCounter.init(self.allocator);
        defer var_counter.deinit();
        try self.dfsBuildBlock(&cfg.blocks, &ssa_context.blocks, dom_node, &var_counter);
        return ssa_context;
    }

    fn dfsBuildBlock(
        self: Self,
        blocks: *const std.AutoHashMap(u32, *AnnotatedBlock),
        dest: *std.AutoHashMap(u32, *ssa.Block),
        dom_node: *dom.DominanceNode,
        var_counter: *VariableCounter,
    ) !void {
        const block = blocks.get(dom_node.id).?;

        const need_pop = block.* == .Sequential;
        //After leaving the block, we need to pop the variables from the counter
        //So dominator siblings can use the same variable names
        var var_on_entry = std.StringHashMap(ssa.Variable).init(self.allocator);
        defer var_on_entry.deinit();
        if (need_pop) {
            var it = block.*.Sequential.assigned_vars.keyIterator();
            while (it.next()) |name_ptr| {
                const name = name_ptr.*;
                const latest_version = var_counter.getLatest(name);
                if (latest_version != null) {
                    try var_on_entry.put(name, latest_version.?);
                }
            }
        }

        try dest.put(dom_node.id, try self.buildBlock(self.allocator, block.*, var_counter));
        for (dom_node.children.items) |child| {
            try self.dfsBuildBlock(blocks, dest, child, var_counter);
        }

        if (need_pop) {
            //Pop the variables from the counter
            // Fix this , use recursive instead
            var var_it = var_on_entry.iterator();
            while (var_it.next()) |entry| {
                const name = entry.key_ptr.*;
                const version = entry.value_ptr.*;
                try var_counter.popUntil(name, version.version);
            }
        }
    }

    fn buildBlock(
        self: Self,
        allocator: std.mem.Allocator,
        block: AnnotatedBlock,
        counter: *VariableCounter,
    ) !*ssa.Block {
        const ssa_block = try allocator.create(ssa.Block);
        switch (block) {
            .Decision => |decision| {
                var instructions = std.ArrayList(ssa.Instruction).init(allocator);
                try renamePhis(allocator, decision.phis, &instructions, counter);
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

                try renamePhis(allocator, sequential.phis, &instructions, counter);
                for (sequential.inner.*.statements.items) |stmt| {
                    try self.handleStatement(stmt, &instructions, counter);
                }

                var successor: u32 = std.math.maxInt(u32);
                if (sequential.inner.*.successor != null) {
                    successor = getBlockId(sequential.inner.*.successor.?);
                }
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
                    const lhs = ssa.Value{
                        .Var = try vars.add(assign.lhs),
                    };
                    const inst = ssa.Instruction{ .Assignment = ssa.Assignment{
                        .lhs = lhs,
                        .rhs = ssa.AssignValue{
                            .Value = rhs,
                        },
                    } };
                    try dest.append(inst);
                }
            },
            .assign_list => |assign_list| {
                const array_root = attemptFindArrayRoot(assign_list.lhs.*);
                // If the array root is null, for example,
                // [1, 2, 3][0] = 4
                // Then we can ignore this statement
                if (array_root == null) {
                    return;
                }
                const is_global_var = self.context.global_vars.contains(array_root.?);
                const idx = try self.handleExpr(assign_list.idx, dest, vars);
                const array = try self.handleExpr(assign_list.lhs, dest, vars);
                const value = try self.handleExpr(assign_list.rhs, dest, vars);

                if (is_global_var) {
                    const inst = ssa.Instruction{ .WriteArr = ssa.ArrayWriteExpr{
                        .array = array,
                        .idx = idx,
                        .value = value,
                    } };
                    try dest.append(inst);
                } else {
                    const new_value = ssa.Value{
                        .Var = try vars.add(array_root.?),
                    };
                    const inst = ssa.Instruction{ .Assignment = ssa.Assignment{
                        .lhs = new_value,
                        .rhs = ssa.AssignValue{ .ArrayWrite = ssa.ArrayWriteExpr{
                            .array = array,
                            .idx = idx,
                            .value = value,
                        } },
                    } };
                    try dest.append(inst);
                }
            },
            .@"return" => |ret| {
                const value = try self.handleExpr(ret, dest, vars);
                const inst = ssa.Instruction{ .Return = value };
                try dest.append(inst);
            },
            .expr => |expr| {
                const value = try self.handleExpr(expr, dest, vars);
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{
                    .lhs = ssa.Value{ .Var = try vars.add("tmp") },
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

    fn renamePhis(allocator: std.mem.Allocator, phis: std.StringHashMap(void), dest: *std.ArrayList(ssa.Instruction), vars: *VariableCounter) !void {
        var it = phis.keyIterator();
        while (it.next()) |phi| {
            const name = try vars.add(phi.*);
            const inst = ssa.Instruction{
                .Assignment = ssa.Assignment{ .lhs = ssa.Value{
                    .Var = name,
                }, .rhs = ssa.AssignValue{ .Phi = ssa.PhiValues{
                    .values = std.ArrayList(ssa.Value).init(allocator),
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
                const tmp = ssa.Value{ .Var = try vars.add("tmp") };
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{
                    .lhs = tmp,
                    .rhs = ssa.AssignValue{ .BinOp = ssa.BinOpExpr{
                        .lhs = lhs,
                        .rhs = rhs,
                        .op = expr.*.bin_op.op,
                    } },
                } };
                try dest.append(inst);
                return tmp;
            },
            ast.ExprTag.ident => {
                const is_global_var = self.context.global_vars.contains(expr.*.ident);
                if (is_global_var) {
                    const tmp = ssa.Value{ .Var = try vars.add("tmp") };
                    const load_inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .lhs = tmp, .rhs = ssa.AssignValue{
                        .Load = expr.*.ident,
                    } } };
                    try dest.append(load_inst);
                    return tmp;
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
                const tmp = ssa.Value{ .Var = try vars.add("tmp") };
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .lhs = tmp, .rhs = ssa.AssignValue{ .FunctionCall = ssa.FunctionCallExpr{
                    .name = expr.function_call.name,
                    .args = args,
                } } } };
                try dest.append(inst);
                return tmp;
            },
            ast.ExprTag.list_access => {
                const list = try self.handleExpr(expr.*.list_access.list, dest, vars);
                const idx = try self.handleExpr(expr.*.list_access.idx, dest, vars);
                const tmp = ssa.Value{ .Var = try vars.add("tmp") };
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .lhs = tmp, .rhs = ssa.AssignValue{ .ArrayRead = ssa.ArrayReadExpr{
                    .array = list,
                    .idx = idx,
                } } } };
                try dest.append(inst);
                return tmp;
            },
            ast.ExprTag.list_declare => {
                var values = std.ArrayList(ssa.Value).init(self.allocator);
                for (expr.*.list_declare.values.items) |item| {
                    try values.append(try self.handleExpr(item, dest, vars));
                }
                const tmp = ssa.Value{ .Var = try vars.add("tmp") };
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .lhs = tmp, .rhs = ssa.AssignValue{
                    .ListValue = values,
                } } };
                try dest.append(inst);
                return tmp;
            },
            ast.ExprTag.not_expr => {
                const inner = try self.handleExpr(expr.*.not_expr, dest, vars);
                const tmp = ssa.Value{ .Var = try vars.add("tmp") };
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .lhs = tmp, .rhs = ssa.AssignValue{
                    .Not = inner,
                } } };
                try dest.append(inst);
                return tmp;
            },
            ast.ExprTag.unary_expr => {
                const inner = try self.handleExpr(expr.*.unary_expr, dest, vars);
                const tmp = ssa.Value{ .Var = try vars.add("tmp") };
                const inst = ssa.Instruction{ .Assignment = ssa.Assignment{ .lhs = tmp, .rhs = ssa.AssignValue{
                    .Unary = inner,
                } } };
                try dest.append(inst);
                return tmp;
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
    try identifyGlobalVars(cfgIR, &global_vars);

    var functions = std.StringHashMap(AnnotatedCfg).init(allocator);
    var it = cfgIR.functions.iterator();
    while (it.next()) |entry| {
        try functions.put(entry.key_ptr.*, try annotateCfg(allocator, &global_vars, entry.value_ptr));
    }
    const context = AnnotatedContext{
        .global_vars = global_vars,
        .functions = functions,
        .main = try annotateCfg(allocator, &global_vars, &cfgIR.main),
    };
    var constructor = SSAConstructor.init(allocator, context);
    return try constructor.buildSSA();
}

fn annotateCfg(allocator: std.mem.Allocator, global_vars: *std.StringHashMap(void), cfg: *const cfgir.ControlFlowGraph) !AnnotatedCfg {
    var blocks = std.AutoHashMap(u32, *AnnotatedBlock).init(allocator);
    var it = cfg.blocks.valueIterator();
    while (it.next()) |item| {
        var used_vars = std.StringHashMap(void).init(allocator);
        try identifyUsedVars(item.*, &used_vars);
        defer used_vars.deinit();
        switch (item.*.*) {
            cfgir.BlockTag.Decision => {
                const block = try allocator.create(AnnotatedBlock);
                block.* = AnnotatedBlock{
                    .Decision = AnnotatedDecisionBlock{
                        .inner = &item.*.*.Decision,
                        .used_vars = try used_vars.clone(),
                        .phis = std.StringHashMap(void).init(allocator),
                    },
                };
                try blocks.put(item.*.*.Decision.id, block);
            },
            cfgir.BlockTag.Sequential => {
                var assigned_vars = std.StringHashMap(void).init(allocator);
                defer assigned_vars.deinit();
                try identifyAssignedVars(item.*, &assigned_vars);
                const block = try allocator.create(AnnotatedBlock);
                block.* = AnnotatedBlock{
                    .Sequential = AnnotatedNormalBlock{
                        .inner = &item.*.*.Sequential,
                        .used_vars = try used_vars.clone(),
                        .assigned_vars = try assigned_vars.clone(),
                        .phis = std.StringHashMap(void).init(allocator),
                    },
                };
                try blocks.put(item.*.*.Sequential.id, block);
            },
        }
    }
    var annotated = AnnotatedCfg{
        .blocks = blocks,
        .entry = 0,
        .exit = math.maxInt(u32),
        .dom_tree = try dom.computeDominanceTree(allocator, cfg),
    };
    try insertPhis(global_vars, &annotated);
    return annotated;
}

fn insertPhis(global_var: *std.StringHashMap(void), cfg: *AnnotatedCfg) !void {
    var it = cfg.blocks.valueIterator();
    while (it.next()) |block| {
        switch (block.*.*) {
            AnnotatedBlockTag.Decision => {
                var var_it = block.*.*.Decision.used_vars.keyIterator();
                while (var_it.next()) |used_var| {
                    if (global_var.contains(used_var.*)) {
                        continue;
                    }
                    try block.*.*.Decision.phis.put(used_var.*, void{});
                }
            },
            AnnotatedBlockTag.Sequential => {
                var var_it = block.*.*.Sequential.used_vars.keyIterator();
                while (var_it.next()) |used_var| {
                    if (global_var.contains(used_var.*)) {
                        continue;
                    }
                    try block.*.*.Sequential.phis.put(used_var.*, void{});
                }
            },
        }
    }
}

fn identifyGlobalVars(cfg: *const CfgIR, global_vars: *std.StringHashMap(void)) !void {
    var it = cfg.main.blocks.valueIterator();
    while (it.next()) |block| {
        try identifyAssignedVars(block.*, global_vars);
    }
}

fn identifyUsedVars(block: *CfgBlock, used_vars: *std.StringHashMap(void)) !void {
    switch (block.*) {
        cfgir.BlockTag.Decision => {
            try identifyExprUsedVars(&block.*.Decision.condition, used_vars);
        },
        cfgir.BlockTag.Sequential => {
            for (block.*.Sequential.statements.items) |stmt| {
                switch (stmt) {
                    .assign => {
                        try identifyExprUsedVars(stmt.assign.rhs, used_vars);
                    },
                    .assign_list => {
                        try identifyExprUsedVars(stmt.assign_list.idx, used_vars);
                        try identifyExprUsedVars(stmt.assign_list.lhs, used_vars);
                        try identifyExprUsedVars(stmt.assign_list.rhs, used_vars);
                    },
                    .@"return" => {
                        try identifyExprUsedVars(stmt.@"return", used_vars);
                    },
                    .expr => {
                        try identifyExprUsedVars(stmt.expr, used_vars);
                    },
                    .print => {
                        try identifyExprUsedVars(stmt.print.value, used_vars);
                    },
                }
            }
        },
    }
}

fn identifyExprUsedVars(expr: *ast.Expr, used_vars: *std.StringHashMap(void)) !void {
    switch (expr.*) {
        ast.ExprTag.ident => {
            try used_vars.put(expr.*.ident, void{});
        },
        ast.ExprTag.bin_op => {
            try identifyExprUsedVars(expr.*.bin_op.lhs, used_vars);
            try identifyExprUsedVars(expr.*.bin_op.rhs, used_vars);
        },
        ast.ExprTag.function_call => {
            for (expr.*.function_call.args.items) |arg| {
                try identifyExprUsedVars(arg, used_vars);
            }
        },
        ast.ExprTag.list_access => {
            try identifyExprUsedVars(expr.*.list_access.list, used_vars);
            try identifyExprUsedVars(expr.*.list_access.idx, used_vars);
        },
        ast.ExprTag.list_declare => {
            for (expr.*.list_declare.values.items) |value| {
                try identifyExprUsedVars(value, used_vars);
            }
        },
        ast.ExprTag.not_expr => {
            try identifyExprUsedVars(expr.*.not_expr, used_vars);
        },
        ast.ExprTag.unary_expr => {
            try identifyExprUsedVars(expr.*.unary_expr, used_vars);
        },
        ast.ExprTag.@"const" => {},
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
        std.debug.print("{}\n", .{err});
        std.debug.print("{s}\n", .{parser.diagnostics});
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
