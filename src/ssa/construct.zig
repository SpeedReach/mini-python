const cfgir = @import("../cfgir/cfgir.zig");
const ast = @import("../ast/ast.zig");
const CfgIR = cfgir.Program;
const CfgBlock = cfgir.Block;
const CfgNormalBlock = cfgir.NormalBlock;
const CfgDecisionBlock = cfgir.DecisionBlock;

const ssa = @import("./ssa.zig");
const math = std.math;
const std = @import("std");

pub const CfgWithVars = struct {
    blocks: std.AutoHashMap(u32, *BlockWithVars),
    entry: u32,
    exit: u32,
};

pub const BlockWithVarsTag = enum { Sequential, Decision };

pub const BlockWithVars = union(BlockWithVarsTag) { Sequential: NormalBlockWithVars, Decision: DecisionBlockWithVars };

pub const NormalBlockWithVars = struct {
    inner: *CfgNormalBlock,
    used_vars: std.StringHashMap(void),
    assigned_vars: std.StringHashMap(void),
};

pub const DecisionBlockWithVars = struct {
    inner: *CfgDecisionBlock,
    used_vars: std.StringHashMap(void),
};

pub const SSAConstructor = struct {
    main: CfgWithVars,
    functions: std.StringHashMap(CfgWithVars),
    global_vars: std.StringHashMap(void),

    pub fn init(allocator: std.mem.Allocator, cfgIR: *const CfgIR) !SSAConstructor {
        var global_vars = std.StringHashMap(void).init(allocator);
        try identifyGlobalVars(cfgIR, &global_vars);

        var functions = std.StringHashMap(CfgWithVars).init(allocator);
        var it = cfgIR.functions.iterator();
        while (it.next()) |entry| {
            try functions.put(entry.key_ptr.*, try annotateCfgWithVars(allocator, entry.value_ptr));
        }

        return SSAConstructor{
            .global_vars = global_vars,
            .main = try annotateCfgWithVars(allocator, &cfgIR.main),
            .functions = functions,
        };
    }
};

fn annotateCfgWithVars(allocator: std.mem.Allocator, cfg: *const cfgir.ControlFlowGraph) !CfgWithVars {
    var blocks = std.AutoHashMap(u32, *BlockWithVars).init(allocator);
    var it = cfg.blocks.valueIterator();
    while (it.next()) |item| {
        var used_vars = std.StringHashMap(void).init(allocator);
        try identifyUsedVars(item.*, &used_vars);
        defer used_vars.deinit();
        switch (item.*.*) {
            cfgir.BlockTag.Decision => {
                const block = try allocator.create(BlockWithVars);
                block.* = BlockWithVars{ .Decision = DecisionBlockWithVars{
                    .inner = &item.*.*.Decision,
                    .used_vars = try used_vars.clone(),
                } };
                try blocks.put(item.*.*.Decision.id, block);
            },
            cfgir.BlockTag.Sequential => {
                var assigned_vars = std.StringHashMap(void).init(allocator);
                defer assigned_vars.deinit();
                try identifyAssignedVars(item.*, &assigned_vars);
                const block = try allocator.create(BlockWithVars);
                block.* = BlockWithVars{ .Sequential = NormalBlockWithVars{
                    .inner = &item.*.*.Sequential,
                    .used_vars = try used_vars.clone(),
                    .assigned_vars = try assigned_vars.clone(),
                } };
                try blocks.put(item.*.*.Sequential.id, block);
            },
        }
    }
    return CfgWithVars{
        .blocks = blocks,
        .entry = 0,
        .exit = math.maxInt(u32),
    };
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
