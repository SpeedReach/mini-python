pub const std = @import("std");
pub const ast = @import("../ast/ast.zig");

pub const Ident = []const u8;

pub const Def = struct {
    name: Ident,
    params: []const Ident,
    body: ControlFlowGraph,
};

pub const Program = struct {
    defs: std.ArrayList(Def),
    main: ControlFlowGraph,
    allocator: std.heap.ArenaAllocator,

    pub fn fromAst(tree: *const ast.AstFile) Program {
        const allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        const self = Program{
            .defs = std.ArrayList(Def).init(allocator),
            .main = undefined,
            .allocator = allocator,
        };
        for (tree.defs) |def| {
            self.defs.append(self.astDefToCFG(def));
        }

        return self;
    }

    pub fn deinit(self: *Program) void {
        self.allocator.deinit();
    }
};

const UnexpectError = error{UnexpectError};
const CFGError = UnexpectError || std.mem.Allocator.Error;

pub const CFGConstructor = struct {
    allocator: std.mem.Allocator,
    prefix: []const u8,
    block_idx: u32,
    blocks: std.AutoHashMap(u32, *Block),
    scope_control_stack: std.ArrayList(*Block),
    /// CurrentBlock should always be a NormalBlock (Sequential)
    current_block: *Block,

    fn init(allocator: std.mem.Allocator, prefix: []const u8) !CFGConstructor {
        const block = try allocator.create(Block);
        var blocks = std.AutoHashMap(u32, *Block).init(allocator);
        block.* = Block{ .Sequential = NormalBlock.init(allocator, 0, try std.fmt.allocPrint(allocator, "{s}%{d}", .{ prefix, 0 })) };

        try blocks.put(0, block);
        return CFGConstructor{
            .allocator = allocator,
            .block_idx = 1,
            .prefix = prefix,
            .current_block = block,
            .blocks = blocks,
            .scope_control_stack = std.ArrayList(*Block).init(allocator),
        };
    }

    pub fn build(self: *CFGConstructor) !ControlFlowGraph {
        const cfg = ControlFlowGraph{ .blocks = self.blocks, .entry = self.blocks.get(0).?, .exit = self.current_block };
        return cfg;
    }

    pub fn addStatements(self: *CFGConstructor, statements: []ast.Statement) CFGError!void {
        for (statements) |statement| {
            switch (statement) {
                .simple_statement => |s_s| {
                    try self.current_block.Sequential.statements.append(s_s);
                },
                .for_in_statement => |for_in| {
                    try self.handleForIn(for_in);
                },
                .if_statement => |if_s| {
                    try self.handleIf(if_s);
                },
                .if_else_statement => |if_else_s| {
                    try self.handleIfElse(if_else_s);
                },
            }
        }
    }

    fn handleIfElse(self: *CFGConstructor, statement: ast.IfElseStatement) !void {
        const if_cond_block = try self.createDecisionBlock("ifCondBlock", statement.condition);
        // link currentBlock => ifCondBlock
        self.current_block.Sequential.successor = if_cond_block;
        try if_cond_block.Decision.predecessors.append(self.current_block);

        // ifBody, the block that contains the body of the if statement
        // is executed if the ifCondBlock is true
        var if_body = try self.createSequentialBlock("ifBody");
        // link ifCondBlock to ifBody when the condition is true
        if_cond_block.Decision.then_block = if_body;
        try if_body.Sequential.predecessors.append(if_cond_block);

        // add body to statement
        self.current_block = if_body;
        try self.addStatements(statement.if_body.statements.items);

        const if_last_block = self.current_block;

        const else_block = try self.createSequentialBlock("elseBlock");
        // link ifCondBlock to elseBlock when the condition is false
        if_cond_block.Decision.else_block = else_block;
        try else_block.Sequential.predecessors.append(if_cond_block);
        // add else body to statement
        self.current_block = else_block;
        try self.addStatements(statement.else_body.statements.items);
        const else_last_block = self.current_block;

        const exit_block = try self.createSequentialBlock("");
        self.current_block = exit_block;

        // link if and else body to exit block
        try exit_block.Sequential.predecessors.append(if_last_block);
        try exit_block.Sequential.predecessors.append(exit_block);
        if_last_block.Sequential.successor = exit_block;
        else_last_block.Sequential.successor = exit_block;
    }

    fn createDecisionBlock(self: *CFGConstructor, name: []const u8, condition: ast.Expr) !*Block {
        const block = try self.allocator.create(Block);
        block.* = Block{
            .Decision = try DecisionBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(self.allocator, "{s}%{d}%{s}", .{ self.prefix, self.block_idx, name }), condition),
        };
        try self.blocks.put(self.block_idx, block);
        self.block_idx += 1;
        return block;
    }

    fn createSequentialBlock(self: *CFGConstructor, name: []const u8) !*Block {
        const block = try self.allocator.create(Block);
        block.* = Block{ .Sequential = NormalBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(self.allocator, "{s}%{d}%{s}", .{ self.prefix, self.block_idx, name })) };
        try self.blocks.put(self.block_idx, block);
        self.block_idx += 1;
        return block;
    }

    fn handleIf(self: *CFGConstructor, statement: ast.IfStatement) !void {
        const if_cond_block = try self.createDecisionBlock("ifCondBlock", statement.condition.*);
        // link currentBlock => ifCondBlock
        self.current_block.Sequential.successor = if_cond_block;
        try if_cond_block.Decision.predecessors.append(self.current_block);

        // ifBody, the block that contains the body of the if statement
        // is executed if the ifCondBlock is true
        var if_body = try self.createSequentialBlock("ifBody");
        // link ifCondBlock to ifBody when the condition is true
        if_cond_block.Decision.then_block = if_body;
        try if_body.Sequential.predecessors.append(if_cond_block);

        // add body to statement
        self.current_block = if_body;
        try self.addStatements(statement.body.statements.items);

        const exit_block = try self.allocator.create(Block);
        exit_block.* = Block{ .Sequential = NormalBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(self.allocator, "{s}%{d}ifExit", .{ self.prefix, self.block_idx })) };
        try self.blocks.put(self.block_idx, exit_block);
        self.block_idx += 1;

        // link ifCondBlock to exitBlock when the condition is false
        if_cond_block.Decision.else_block = exit_block;
        try exit_block.Sequential.predecessors.append(if_cond_block);

        // link currentBlock to exitBlock
        // if the ifBody doesn't contain any control flow statement
        // then currentBlock would still be ifBody
        self.current_block.Sequential.successor = exit_block;
        try exit_block.Sequential.predecessors.append(self.current_block);
        self.current_block = exit_block;
    }

    fn handleForIn(self: *CFGConstructor, statement: ast.ForInStatement) !void {

        // add i=0; n=len(iterable) to currentBlock
        // indexIdent = 0
        const index_ident = try formatForIndex(self.allocator, self.prefix, self.block_idx);
        const index_expr: *Expr = try self.allocator.create(ast.Expr);
        index_expr.* = ast.Expr{ .@"const" = ast.Const{ .int = 0 } };
        try self.current_block.Sequential.statements.append(ast.SimpleStatement{ .assign = ast.SimpleAssignment{
            .lhs = index_ident,
            .rhs = index_expr,
        } });
        // n = len(iterable)
        const nIdent = try formatForN(self.allocator, self.prefix, self.block_idx);
        const len_expr = try self.allocator.create(ast.Expr);
        var len_args = try std.ArrayList(*const Expr).initCapacity(self.allocator, 1);
        try len_args.insert(0, statement.iterable);
        len_expr.* = ast.Expr{ .function_call = ast.FunctionCall{ .args = len_args, .name = "len" } };
        try self.current_block.Sequential.statements.append(ast.SimpleStatement{ .assign = ast.SimpleAssignment{ .lhs = nIdent, .rhs = len_expr } });

        // forConditionBlock, the block that contains the condition of the for loop
        // if i < n goto forBody else goto forExit
        const condition = ast.Expr{ .bin_op = ast.BinOpExpr{ .op = ast.BinOp.lt, .lhs = &ast.Expr{ .ident = index_ident }, .rhs = &ast.Expr{ .ident = nIdent } } };
        var for_condition_block = try self.allocator.create(Block);
        for_condition_block.* = Block{
            .Decision = try DecisionBlock.init(
                self.allocator,
                self.block_idx,
                try std.fmt.allocPrint(self.allocator, "{s}%{d}%forCondBlock", .{ self.prefix, self.block_idx }),
                condition,
            ),
        };
        try self.blocks.put(self.block_idx, for_condition_block);
        self.block_idx += 1;
        // link currentBlock => forConditionBlock
        self.current_block.Sequential.successor = for_condition_block;
        try for_condition_block.Decision.predecessors.append(self.current_block);

        // forBody, the block that contains the body of the for loop
        // is executed if the forConditionBlock is true
        var for_body = try self.allocator.create(Block);
        for_body.* = Block{ .Sequential = NormalBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(self.allocator, "{s}%{d}forBody", .{ self.prefix, self.block_idx })) };
        try self.blocks.put(self.block_idx, for_body);
        self.block_idx += 1;
        // link forConditionBlock to forBody when the condition is true
        for_condition_block.Decision.then_block = for_body;
        try for_body.Sequential.predecessors.append(for_condition_block);

        // indexIndet = indexIndex + 1
        const increment_expr = try self.allocator.create(ast.Expr);
        const lhs = try self.allocator.create(ast.Expr);
        lhs.* = ast.Expr{ .ident = index_ident };
        const rhs = try self.allocator.create(ast.Expr);
        rhs.* = ast.Expr{ .@"const" = ast.Const{ .int = 1 } };
        increment_expr.* = ast.Expr{ .bin_op = ast.BinOpExpr{ .op = ast.BinOp.add, .rhs = rhs, .lhs = lhs } };
        try for_body.Sequential.statements.append(ast.SimpleStatement{ .assign = ast.SimpleAssignment{
            .lhs = index_ident,
            .rhs = increment_expr,
        } });

        // add the body of the for loop to forBody
        // we do a recursive call here, because the body of the for loop can contain another for loop
        self.current_block = for_body;
        try self.scope_control_stack.append(for_condition_block);
        try self.addStatements(statement.body.statements.items);
        _ = self.scope_control_stack.pop();

        // link for_body to forConditionBlock,
        // if the for_body doesn't contain any control flow statement
        // then currentBlock would still be for_body
        // otherwise, currentBlock would be the last block of the for_body
        self.current_block.Sequential.successor = for_condition_block;
        try for_condition_block.Decision.predecessors.append(self.current_block);

        // determine the exitBlock,
        // if scopeControlStack is empty, then we create a NormalBlock as exit
        var exit_block = self.scope_control_stack.getLastOrNull();
        if (exit_block == null) {
            exit_block = try self.allocator.create(Block);
            exit_block.?.* = Block{
                .Sequential = NormalBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(
                    self.allocator,
                    "{s}%{d}",
                    .{ self.prefix, self.block_idx },
                )),
            };
            try self.blocks.put(self.block_idx, exit_block.?);
            self.block_idx += 1;
        }

        switch (exit_block.?.*) {
            .Sequential => {
                try exit_block.?.Sequential.predecessors.append(for_body);
            },
            .Decision => {
                try exit_block.?.Decision.predecessors.append(for_body);
            },
        }

        for_condition_block.Decision.else_block = exit_block;
    }
};

pub fn astDefToCFG(allocator: std.mem.Allocator, def: ast.Def) Def {
    const cfg = astStatementsToCFG(allocator, def.body.statements);
    return Def{
        .name = def.name,
        .params = def.params,
        .body = cfg,
    };
}

fn astStatementsToCFG(allocator: std.mem.Allocator, statements: []ast.Statement, prefix: []const u8) !ControlFlowGraph {
    var constructor = try CFGConstructor.init(allocator, prefix);
    try constructor.addStatements(statements);
    return constructor.build();
}

fn intToString(allocator: std.mem.Allocator, int: u32) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{int});
}

fn formatForIndex(allocator: std.mem.Allocator, prefix: []const u8, blockIndex: u32) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}%{d}forIndex", .{ prefix, blockIndex });
}

fn formatForN(allocator: std.mem.Allocator, prefix: []const u8, blockIndex: u32) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}%{d}forN", .{ prefix, blockIndex });
}

/// Block naming:
/// blocks that belong to a function are named as follows:
///    <function_name>%<block_number>
/// blocks that belong to the main function are named as follows:
///   main%<block_number>
/// for example , the entry block should be named main%0
pub const ControlFlowGraph = struct {
    blocks: std.AutoHashMap(u32, *Block),
    entry: *Block,
    exit: *Block,
};

pub const BlockTag = enum { Sequential, Decision };

pub const Block = union(BlockTag) { Sequential: NormalBlock, Decision: DecisionBlock };

pub const NormalBlock = struct {
    id: u32,
    name: []const u8,
    statements: std.ArrayList(Statement),
    successor: ?*Block,
    predecessors: std.ArrayList(*Block),

    pub fn init(allocator: std.mem.Allocator, id: u32, name: []const u8) NormalBlock {
        return NormalBlock{ .name = name, .id = id, .statements = std.ArrayList(Statement).init(allocator), .successor = null, .predecessors = std.ArrayList(*Block).init(allocator) };
    }
};

pub const DecisionBlock = struct {
    id: u32,
    name: []const u8,
    condition: Expr,
    predecessors: std.ArrayList(*Block),
    then_block: ?*Block,
    else_block: ?*Block,

    pub fn init(allocator: std.mem.Allocator, id: u32, name: []const u8, condition: Expr) !DecisionBlock {
        return DecisionBlock{ .name = name, .id = id, .condition = condition, .predecessors = std.ArrayList(*Block).init(allocator), .then_block = null, .else_block = null };
    }
};

pub const StatementTag = enum { @"return", assign, assign_list, print, expr };

pub const Statement = ast.SimpleStatement;

pub const Expr = ast.Expr;

const testing = std.testing;
const utils = @import("../utils/utils.zig");
test "for " {
    // for a in b:
    //    for x in y:
    //       if awrawr:
    var arenaAllocator = std.heap.ArenaAllocator.init(testing.allocator);
    defer arenaAllocator.deinit();
    const allocator = arenaAllocator.allocator();
    var statements = std.ArrayList(ast.Statement).init(allocator);
    var outerForBody = std.ArrayList(ast.Statement).init(allocator);
    var innerForBody = std.ArrayList(ast.Statement).init(allocator);
    var innerBodyStatements = std.ArrayList(ast.Statement).init(allocator);
    try innerBodyStatements.append(ast.Statement{ .simple_statement = ast.SimpleStatement{ .expr = &ast.Expr{ .ident = "awrawr" } } });
    try innerForBody.append(ast.Statement{ .if_statement = ast.IfStatement{
        .condition = &ast.Expr{ .ident = "awrawr" },
        .body = ast.Suite{ .statements = innerBodyStatements },
    } });
    try outerForBody.append(ast.Statement{ .for_in_statement = ast.ForInStatement{
        .var_name = "x",
        .iterable = &ast.Expr{ .ident = "y" },
        .body = ast.Suite{
            .statements = innerForBody,
        },
    } });
    const outerFor = ast.ForInStatement{ .var_name = "a", .iterable = &ast.Expr{ .ident = "b" }, .body = ast.Suite{ .statements = outerForBody } };

    try statements.append(ast.Statement{ .for_in_statement = outerFor });

    const cfg = try astStatementsToCFG(allocator, statements.items, "abc");
    //try printCfg(cfg);
    try generateMermaidDiagram(cfg, std.io.getStdErr().writer());
}

fn printCfg(cfg: ControlFlowGraph) !void {
    var it = cfg.blocks.iterator();
    while (it.next()) |entry| {
        switch (entry.value_ptr.*.*) {
            .Decision => {
                std.debug.print("\n{d} {s}\n", .{ entry.value_ptr.*.*.Decision.id, entry.value_ptr.*.*.Decision.name });
                std.debug.print("in\n", .{});
                for (entry.value_ptr.*.*.Decision.predecessors.items) |pred| {
                    switch (pred.*) {
                        .Sequential => {
                            std.debug.print("{d},", .{pred.*.Sequential.id});
                        },
                        .Decision => {
                            std.debug.print("{d},", .{pred.*.Decision.id});
                        },
                    }
                }
                std.debug.print("\n", .{});
                const thenBlock = entry.value_ptr.*.*.Decision.then_block.?.*;
                std.debug.print("then", .{});

                switch (thenBlock) {
                    .Sequential => {
                        std.debug.print("{d}\n", .{thenBlock.Sequential.id});
                    },
                    .Decision => {
                        std.debug.print("{d}\n", .{thenBlock.Decision.id});
                    },
                }
                const elseBlock = entry.value_ptr.*.*.Decision.else_block.?.*;
                std.debug.print("else ", .{});
                switch (entry.value_ptr.*.*.Decision.else_block.?.*) {
                    .Sequential => {
                        std.debug.print("{d}\n", .{elseBlock.Sequential.id});
                    },
                    .Decision => {
                        std.debug.print("{d}\n", .{elseBlock.Decision.id});
                    },
                }
            },
            .Sequential => {
                std.debug.print("\n{d} {s}\n", .{ entry.value_ptr.*.*.Sequential.id, entry.value_ptr.*.*.Sequential.name });
                std.debug.print("in\n", .{});
                for (entry.value_ptr.*.*.Sequential.predecessors.items) |pred| {
                    switch (pred.*) {
                        .Sequential => {
                            std.debug.print("{d},", .{pred.*.Sequential.id});
                        },
                        .Decision => {
                            std.debug.print("{d},", .{pred.*.Decision.id});
                        },
                    }
                }
                std.debug.print("\nout\n", .{});
                const maySucc = entry.value_ptr.*.*.Sequential.successor;
                if (maySucc == null) {
                    std.debug.print("no successor\n", .{});
                    continue;
                }
                const succ = maySucc.?;
                switch (succ.*) {
                    .Sequential => {
                        std.debug.print("{d},", .{succ.*.Sequential.id});
                    },
                    .Decision => {
                        std.debug.print("{d},", .{succ.*.Decision.id});
                    },
                }
                std.debug.print("\n", .{});
            },
        }
    }
}

pub fn generateMermaidDiagram(cfg: ControlFlowGraph, writer: anytype) !void {
    // Start the mermaid graph definition
    try writer.writeAll("graph TD\n");

    var block_it = cfg.blocks.iterator();
    while (block_it.next()) |entry| {
        const block = entry.value_ptr.*.*;

        switch (block) {
            .Sequential => |sequential| {
                // Style sequential blocks as rectangles
                try writer.print("    {d}[\"{s}\"]\n", .{ sequential.id, sequential.name });

                // Draw edge to successor if it exists
                if (sequential.successor) |succ| {
                    try writer.print("    {d} --> {d}\n", .{ sequential.id, switch (succ.*) {
                        .Sequential => |s| s.id,
                        .Decision => |d| d.id,
                    } });
                }
            },
            .Decision => |decision| {
                // Style decision blocks as diamonds
                try writer.print("    {d}{{\"{s}\"}}\n", .{ decision.id, decision.name });

                // Draw edges for then and else branches
                if (decision.then_block) |then_block| {
                    try writer.print("    {d} -->|\"yes\"| {d}\n", .{ decision.id, switch (then_block.*) {
                        .Sequential => |s| s.id,
                        .Decision => |d| d.id,
                    } });
                }

                if (decision.else_block) |else_block| {
                    try writer.print("    {d} -->|\"no\"| {d}\n", .{ decision.id, switch (else_block.*) {
                        .Sequential => |s| s.id,
                        .Decision => |d| d.id,
                    } });
                }
            },
        }
    }
}
