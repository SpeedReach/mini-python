const std = @import("std");

pub const Program = struct {
    functions: std.AutoHashMap([]const u8, FunctionContext),
    global_vars: std.AutoHashMap([]const u8, void),
    main: FunctionContext,
};

pub const FunctionContext = struct {
    assigned_vars: std.AutoHashMap([]const u8, void),
    used_vars: std.AutoHashMap([]const u8, void),
    blocks: std.AutoHashMap(u32, *Block),
    entry: *Block,
    exit: *Block,
};

pub const Value = struct {
    name: []const u8,
    version: u16,
};

pub const BlockTag = enum { Sequential, Decision };

pub const Block = union(BlockTag) { Sequential: NormalBlock, Decision: DecisionBlock };

pub const NormalBlock = struct {
    id: u32,
    name: []const u8,
    instructions: std.ArrayList(Instruction),
    predecessors: std.ArrayList(*Block),
    successor: ?*Block,
    used_vars: std.AutoHashMap([]const u8, void),
    assigned_vars: std.AutoHashMap([]const u8, void),
};

pub const DecisionBlock = struct {
    id: u32,
    name: []const u8,
    instructions: std.ArrayList(Instruction),
    condition: Value,
    predecessors: std.ArrayList(*Block),
    then_block: ?*Block,
    else_block: ?*Block,
    used_vars: std.AutoHashMap([]const u8, void),
};

pub const Instruction = union(enum) {
    Assignment: Assignment,
    Return: Value,
    FunctionCall: FunctionCallExpr,
};

pub const Assignment = struct {
    lhs: Value,
    rhs: AssignValue,
};

pub const AssignValue = union(AssignValueTag) {
    BinOp: BinOpExpr,
    Phi: PhiInstruction,
    FunctionCall: FunctionCallExpr,
    ArrayWrite: ArrayWriteExpr,
    ArrayRead: ArrayReadExpr,
};

pub const AssignValueTag = enum {
    BinOp,
    Phi,
    FunctionCall,
    ArrayWrite,
    ArrayRead,
};

pub const BinOpExpr = struct {
    lhs: Value,
    rhs: Value,
    op: BinOp,
};

pub const FunctionCallExpr = struct {
    name: []const u8,
    args: std.ArrayList(Value),
};

pub const ArrayWriteExpr = struct {
    array: Value,
    idx: Value,
    value: Value,
};

pub const ArrayReadExpr = struct {
    array: Value,
    idx: Value,
};

pub const BinOp = enum { Add, Sub, Mul, Div, Mod, And, Or };

pub const PhiInstruction = struct {
    lhs: Value,
    values: std.ArrayList(Value),
};
