pub const std = @import("std");
pub const ast = @import("../ast/ast.zig");

pub const Ident = []const u8;

const Error = error{ UnexpectError, AlreadyBuilt };
const CFGError = Error || std.mem.Allocator.Error;

pub const Program = struct {
    functions: std.StringHashMap(ControlFlowGraph),
    main: ControlFlowGraph,

    pub fn deinit(self: *Program) void {
        self.main.deinit();
        for (self.functions.valueIterator().items) |cfg| {
            cfg.deinit();
        }
        self.functions.deinit();
    }
};

pub const CFGConstructor = struct {
    allocator: std.mem.Allocator,
    prefix: []const u8,
    block_idx: u32,
    blocks: std.AutoHashMap(u32, *Block),
    /// Stack to keep track of nested control flow statements
    scope_control_stack: std.ArrayList(*Block),
    /// CurrentBlock should always be a NormalBlock (Sequential)
    current_block: *Block,
    end_block: *Block,
    built: bool,
    args: std.ArrayList(Ident),

    fn init(allocator: std.mem.Allocator, prefix: []const u8, args: std.ArrayList(Ident)) !CFGConstructor {
        const block = try allocator.create(Block);
        var blocks = std.AutoHashMap(u32, *Block).init(allocator);
        block.* = Block{ .Sequential = NormalBlock.init(allocator, 0, try std.fmt.allocPrint(allocator, "{s}_{d}_entry", .{ prefix, 0 })) };
        const end = try allocator.create(Block);
        end.* = Block{ .Sequential = NormalBlock.init(allocator, std.math.maxInt(u32), try std.fmt.allocPrint(allocator, "{s}_end", .{prefix})) };
        try blocks.put(0, block);
        try blocks.put(std.math.maxInt(u32), end);
        return CFGConstructor{ .allocator = allocator, .block_idx = 1, .prefix = prefix, .current_block = block, .end_block = end, .blocks = blocks, .scope_control_stack = std.ArrayList(*Block).init(allocator), .built = false, .args = args };
    }

    pub fn deinit(self: *CFGConstructor) void {
        self.scope_control_stack.deinit();
        if (self.built) {
            // Since memory owner ship is transferred to the Program struct, we don't need to deinit the blocks
            return;
        }
        for (self.blocks.valueIterator().items) |block| {
            block.deinit();
        }
        self.blocks.deinit();
        self.args.deinit();
    }

    /// Build the ControlFlowGraph from the constructed blocks
    /// Should be called after adding all statements
    /// And should only be called once
    pub fn build(self: *CFGConstructor) !ControlFlowGraph {
        if (self.built) {
            return Error.AlreadyBuilt;
        }
        //Link last block to end block
        if (self.current_block.Sequential.successor != null and
            self.current_block.Sequential.successor != self.end_block)
        {
            std.debug.print("last block should have no successor when built", .{});
            return Error.UnexpectError;
        }
        self.current_block.Sequential.successor = self.end_block;
        try self.end_block.Sequential.predecessors.append(self.current_block);
        const cfg = ControlFlowGraph{
            .name = self.prefix,
            .args = self.args,
            .blocks = self.blocks,
            .entry = self.blocks.get(0).?,
            .exit = self.end_block,
        };
        return cfg;
    }

    pub fn addStatements(self: *CFGConstructor, statements: []ast.Statement) CFGError!void {
        for (statements) |statement| {
            switch (statement) {
                .simple_statement => |s_s| {
                    try self.current_block.Sequential.statements.append(s_s);
                    if (s_s == .@"return") {
                        //ignore the rest of the statements
                        return;
                    }
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
        if_last_block.Sequential.successor = exit_block;
        try exit_block.Sequential.predecessors.append(if_last_block);
        else_last_block.Sequential.successor = exit_block;
        try exit_block.Sequential.predecessors.append(else_last_block);
    }

    fn createDecisionBlock(self: *CFGConstructor, name: []const u8, condition: ast.Expr) !*Block {
        const block = try self.allocator.create(Block);
        block.* = Block{
            .Decision = try DecisionBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(self.allocator, "{s}_{d}_{s}", .{ self.prefix, self.block_idx, name }), condition),
        };
        try self.blocks.put(self.block_idx, block);
        self.block_idx += 1;
        return block;
    }

    fn createSequentialBlock(self: *CFGConstructor, name: []const u8) !*Block {
        const block = try self.allocator.create(Block);
        block.* = Block{ .Sequential = NormalBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(self.allocator, "{s}_{d}_{s}", .{ self.prefix, self.block_idx, name })) };
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
        exit_block.* = Block{ .Sequential = NormalBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(self.allocator, "{s}_{d}ifExit", .{ self.prefix, self.block_idx })) };
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

        // _iterable = iterable
        const iterable_ident = try std.fmt.allocPrint(self.allocator, "{s}_{d}_iterable", .{ self.prefix, self.block_idx });
        const iterable_assign = ast.SimpleStatement{ .assign = ast.SimpleAssignment{
            .lhs = iterable_ident,
            .rhs = statement.iterable,
        } };
        try self.current_block.Sequential.statements.append(iterable_assign);

        // n = len(iterable)
        const nIdent = try formatForN(self.allocator, self.prefix, self.block_idx);
        const len_expr = try self.allocator.create(ast.Expr);
        const iterable_expr = try self.allocator.create(ast.Expr);
        iterable_expr.* = ast.Expr{ .ident = iterable_ident };
        var len_args = try std.ArrayList(*Expr).initCapacity(self.allocator, 1);
        try len_args.insert(0, iterable_expr);
        len_expr.* = ast.Expr{ .function_call = ast.FunctionCall{ .args = len_args, .name = "len" } };
        try self.current_block.Sequential.statements.append(ast.SimpleStatement{ .assign = ast.SimpleAssignment{ .lhs = nIdent, .rhs = len_expr } });

        // forConditionBlock, the block that contains the condition of the for loop
        // if i < n goto forBody else goto forExit
        const condition_ident_expr = try self.allocator.create(ast.Expr);
        condition_ident_expr.* = ast.Expr{ .ident = index_ident };
        const condition_rhs_expr = try self.allocator.create(ast.Expr);
        condition_rhs_expr.* = ast.Expr{ .ident = nIdent };
        const condition = ast.Expr{ .bin_op = ast.BinOpExpr{ .op = ast.BinOp.lt, .lhs = condition_ident_expr, .rhs = condition_rhs_expr } };
        var for_condition_block = try self.allocator.create(Block);
        for_condition_block.* = Block{
            .Decision = try DecisionBlock.init(
                self.allocator,
                self.block_idx,
                try std.fmt.allocPrint(self.allocator, "{s}_{d}_forCondBlock", .{ self.prefix, self.block_idx }),
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
        for_body.* = Block{ .Sequential = NormalBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(self.allocator, "{s}_{d}forBody", .{ self.prefix, self.block_idx })) };
        try self.blocks.put(self.block_idx, for_body);
        self.block_idx += 1;
        // link forConditionBlock to forBody when the condition is true
        for_condition_block.Decision.then_block = for_body;
        try for_body.Sequential.predecessors.append(for_condition_block);

        // At the start of the forBody, we need to assign the item of the iterable to the loop variable
        // a = iterable[i]
        const iterable_ident_expr = try self.allocator.create(ast.Expr);
        iterable_ident_expr.* = ast.Expr{ .ident = iterable_ident };
        const loop_var_ident = try self.allocator.create(ast.Expr);
        loop_var_ident.* = ast.Expr{ .ident = statement.var_name };
        const loop_var_index = try self.allocator.create(ast.Expr);
        loop_var_index.* = ast.Expr{ .ident = index_ident };
        const loop_var_expr = try self.allocator.create(ast.Expr);
        loop_var_expr.* = ast.Expr{
            .list_access = ast.ListAccess{
                .list = iterable_ident_expr,
                .idx = loop_var_index,
            },
        };
        const loop_var_assign = ast.SimpleStatement{ .assign = ast.SimpleAssignment{
            .lhs = statement.var_name,
            .rhs = loop_var_expr,
        } };
        try for_body.Sequential.statements.append(loop_var_assign);

        // add the body of the for loop to forBody
        // we do a recursive call here, because the body of the for loop can contain another for loop
        self.current_block = for_body;
        try self.addStatements(statement.body.statements.items);

        // At the end of the forBody, we need to increment the index
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

        // link for_body to forConditionBlock,
        // if the for_body doesn't contain any control flow statement
        // then currentBlock would still be for_body
        // otherwise, currentBlock would be the last block of the for_body
        self.current_block.Sequential.successor = for_condition_block;
        try for_condition_block.Decision.predecessors.append(self.current_block);

        // determine the exitBlock,
        // if scopeControlStack is empty, then we create a NormalBlock as exit
        var exit_block = try self.allocator.create(Block);
        exit_block.* = Block{
            .Sequential = NormalBlock.init(self.allocator, self.block_idx, try std.fmt.allocPrint(
                self.allocator,
                "{s}_forexit_{d}",
                .{ self.prefix, self.block_idx },
            )),
        };
        try self.blocks.put(self.block_idx, exit_block);
        self.block_idx += 1;

        try exit_block.Sequential.predecessors.append(for_condition_block);
        self.current_block = exit_block;

        for_condition_block.Decision.else_block = exit_block;
    }
};

pub fn astToCfgIR(allocator: std.mem.Allocator, ast_file: ast.AstFile) !*Program {
    var functions = std.StringHashMap(ControlFlowGraph).init(allocator);
    const main = try astStatementsToCFG(allocator, std.ArrayList(Ident).init(allocator), ast_file.statements.items, "main");
    for (ast_file.defs.items) |def| {
        const args = try def.params.clone();
        const name = try std.fmt.allocPrint(allocator, "__{s}", .{def.name});
        var constructor = try CFGConstructor.init(allocator, name, args);
        try constructor.addStatements(def.body.statements.items);
        try functions.put(def.name, try constructor.build());
    }
    const program = try allocator.create(Program);
    program.* = Program{
        .functions = functions,
        .main = main,
    };
    return program;
}

pub fn astStatementsToCFG(allocator: std.mem.Allocator, args: std.ArrayList(Ident), statements: []ast.Statement, prefix: []const u8) !ControlFlowGraph {
    var constructor = try CFGConstructor.init(allocator, prefix, args);
    try constructor.addStatements(statements);
    return constructor.build();
}

fn intToString(allocator: std.mem.Allocator, int: u32) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{int});
}

fn formatForIndex(allocator: std.mem.Allocator, prefix: []const u8, blockIndex: u32) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}_{d}forIndex", .{ prefix, blockIndex });
}

fn formatForN(allocator: std.mem.Allocator, prefix: []const u8, blockIndex: u32) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}_{d}forN", .{ prefix, blockIndex });
}

/// Block naming:
/// blocks that belong to a function are named as follows:
///    <function_name>%<block_number>
/// blocks that belong to the main function are named as follows:
///   main%<block_number>
/// for example , the entry block should be named main%0
pub const ControlFlowGraph = struct {
    name: []const u8,
    args: std.ArrayList(Ident),
    blocks: std.AutoHashMap(u32, *Block),
    entry: *Block,
    exit: *Block,

    pub fn deinit(self: *ControlFlowGraph) void {
        for (self.blocks.valueIterator().items) |block| {
            block.deinit();
        }
        self.blocks.deinit();
    }
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

    pub fn deinit(self: *NormalBlock) void {
        self.statements.deinit();
        self.predecessors.deinit();
    }
};

pub const DecisionBlock = struct {
    id: u32,
    name: []const u8,
    condition: Expr,
    predecessors: std.ArrayList(*Block),
    then_block: ?*Block,
    else_block: ?*Block,

    pub fn deinit(self: *DecisionBlock) void {
        self.predecessors.deinit();
    }

    pub fn init(allocator: std.mem.Allocator, id: u32, name: []const u8, condition: Expr) !DecisionBlock {
        return DecisionBlock{ .name = name, .id = id, .condition = condition, .predecessors = std.ArrayList(*Block).init(allocator), .then_block = null, .else_block = null };
    }
};

pub const Statement = ast.SimpleStatement;

pub const Expr = ast.Expr;

const testing = std.testing;
const utils = @import("../utils/utils.zig");
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

    const cfg = try astStatementsToCFG(allocator, std.ArrayList(Ident).init(allocator), statements.items, "abc");
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
