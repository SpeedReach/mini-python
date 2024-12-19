pub const std = @import("std");
pub const ast = @import("../ast/ast.zig");

pub const Ident = []const u8;

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

pub fn astDefToCFG(allocator: std.mem.Allocator, def: ast.Def) Def {
    const cfg = astStatementsToCFG(allocator, def.body.statements);
    return Def{
        .name = def.name,
        .params = def.params,
        .body = cfg,
    };
}


pub fn astStatementsToCFG(allocator: std.mem.Allocator, statements: []ast.Statement, prefix: []u8) ControlFlowGraph {
    const blocks = std.AutoHashMap([]u8, *Block).init(allocator);
    var blockIndex = 0;
    var entryBlock: *Block = null;
    var exitBlock: *Block = null;

    const entryBlockName = std.fmt.allocPrint(allocator, "{s}%{d}", .{ prefix, blockIndex });
/// for 
    blockIndex += 1;
    entryBlock = blocks.getOrPut(entryBlockName, null);
}

pub const CFGContext = struct {
    blockIndex: i32,
    exitStack: std.ArrayList(*Block),
};

fn transformFor(allocator: std.mem.Allocator, statement: ast.ForInStatement: prefix: )

pub fn intToString(allocator: std.mem.Allocator, number: i32) ![]u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{number});
}

/// Block naming:
/// blocks that belong to a function are named as follows:
///    <function_name>%<block_number>
/// blocks that belong to the main function are named as follows:
///   main%<block_number>
/// for example , the entry block should be named main%0
pub const ControlFlowGraph = struct {
    blocks: std.AutoHashMap([]u8, *Block),
    entry: *Block,
    exit: *Block,
};

pub const Def = struct {
    name: Ident,
    params: []const Ident,
    body: ControlFlowGraph,
};

pub const Block = struct {
    statements: []Statement,
    transition: BlockTransition,
};

pub const BlockTransitionTag = enum {
    Sequential,
    Conditional,
};

pub const BlockTransition = union(BlockTransitionTag) {
    Sequential: *Block,
    Conditional: Branching,
};

pub const Branching = struct {
    condition: Expr,
    then_block: *Block,
    else_block: *Block,
};

pub const StatementTag = enum { @"return", assign, assign_list, print, expr };

pub const Statement = ast.SimpleStatement;

pub const Expr = ast.Expr;
