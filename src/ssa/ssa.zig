const std = @import("std");

pub const construct = @import("./construct.zig");

pub const Program = struct {
    functions: std.StringHashMap(FunctionContext),
    global_vars: std.StringHashMap(void),
    const_strings: std.StringHashMap(void),
    main: FunctionContext,
};

pub const FunctionContext = struct {
    name: []const u8,
    blocks: std.AutoHashMap(u32, *Block),
};

pub const Value = union(enum) {
    Const: Const,
    Var: Variable,
};

pub const Variable = struct {
    base: []const u8,
    version: u32,
};

pub const BlockTag = enum { Sequential, Decision };

pub const Block = union(BlockTag) { Sequential: NormalBlock, Decision: DecisionBlock };

pub const NormalBlock = struct {
    id: u32,
    name: []const u8,
    instructions: std.ArrayList(Instruction),
    predecessors: std.ArrayList(u32),
    successor: u32,
};

pub const DecisionBlock = struct {
    id: u32,
    name: []const u8,
    instructions: std.ArrayList(Instruction),
    condition: Value,
    predecessors: std.ArrayList(u32),
    then_block: u32,
    else_block: u32,
};

pub const Instruction = union(enum) {
    NoOp: void,
    Assignment: Assignment,
    Return: Value,
    /// Store to global var
    Store: StoreInstruction,
    Print: Value,
};

pub const StoreInstruction = struct {
    value: Value,
    name: []const u8,
};

pub const Assignment = struct {
    variable: Variable,
    rhs: AssignValue,
};

pub const AssignValue = union(enum) {
    BinOp: BinOpExpr,
    Phi: PhiValues,
    FunctionCall: FunctionCallExpr,
    FunctionArg: u8,
    ArrayRead: ArrayReadExpr,
    ArrayWrite: ArrayWriteExpr,
    // Load global var
    Load: []const u8,
    ListValue: std.ArrayList(Value),
    Not: Value,
    Unary: Value,
    Value: Value,
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
    root: []const u8,
    array: Variable,
    idx: Value,
    value: Value,
};

pub const ArrayReadExpr = struct {
    array: Variable,
    idx: Value,
};

pub const BinOp = @import("../ast/ast.zig").BinOp;

pub const PhiValues = struct {
    base: []const u8,
    values: std.ArrayList(PhiValue),
};

pub const PhiValue = struct {
    value: Value,
    block: u32,
};

pub const Const = union(enum) {
    int: i64,
    string: []const u8,
    boolean: bool,
    none,
};

pub fn equal(a: Const, b: Const) bool {
    const compare = cmp(a, b) catch {
        return false;
    };
    return compare == 0;
}

pub fn cmp(a: Const, b: Const) !i64 {
    var a_num: ?i64 = null;
    var b_num: ?i64 = null;
    switch (a) {
        .int => a_num = a.int,
        .boolean => a_num = if (a.boolean) 1 else 0,
        else => {},
    }
    switch (b) {
        .int => b_num = b.int,
        .boolean => b_num = if (b.boolean) 1 else 0,
        else => {},
    }
    if (a_num != null and b_num != null) {
        return a_num.? - b_num.?;
    }

    if (a == .string and b == .string) {
        return strcmp(a.string, b.string);
    }

    return Error.NotSupported;
}

fn strcmp(a: []const u8, b: []const u8) i64 {
    if (a.len != b.len) {
        return if (a.len > b.len) 1 else -1;
    }
    for (a, b) |aChar, bChar| {
        if (aChar != bChar) {
            return if (aChar > bChar) 1 else -1;
        }
    }
    return 0;
}

pub fn isBool(cnst: Const) bool {
    switch (cnst) {
        .boolean => |b| {
            return b;
        },
        .int => |i| {
            return i == 1;
        },
        .string => |s| {
            return s.len != 0;
        },
        .none => {
            return false;
        },
    }
}

pub fn not(cnst: Const) Const {
    switch (cnst) {
        .boolean => return Const{ .boolean = !cnst.boolean },
        .int => return Const{ .boolean = cnst.int == 0 },
        .string => return Const{ .boolean = cnst.string.len == 0 },
        .none => return Const{ .boolean = true },
    }
}

pub const Error = error{
    NotSupported,
};

pub fn unary(cnst: Const) !Const {
    switch (cnst) {
        .int => return Const{ .int = -cnst.int },
        .string => return Error.NotSupported,
        .boolean => return Error.NotSupported,
        .none => return Error.NotSupported,
    }
}

pub fn print(program: Program) void {
    std.debug.print("Main: \n", .{});
    printContext(program.main);
    var it = program.functions.iterator();
    while (it.next()) |entry| {
        std.debug.print("\n\n", .{});
        std.debug.print("{s}:\n", .{entry.key_ptr.*});
        printContext(entry.value_ptr.*);
    }
}

fn printContext(context: FunctionContext) void {
    var it = context.blocks.iterator();
    while (it.next()) |block| {
        printBlock(block.value_ptr.*);
    }
}

fn printBlock(block: *Block) void {
    switch (block.*) {
        Block.Sequential => printSequentialBlock(block.*.Sequential),
        Block.Decision => printDecisionBlock(block.*.Decision),
    }
}

fn printSequentialBlock(block: NormalBlock) void {
    std.debug.print("{d}: Block {s}\n", .{ block.id, block.name });
    for (block.instructions.items) |instruction| {
        printInstruction(instruction);
    }
    std.debug.print("    next {d}\n", .{block.successor});
}

fn printDecisionBlock(block: DecisionBlock) void {
    std.debug.print("{d}: Block {s}\n", .{ block.id, block.name });
    for (block.instructions.items) |instruction| {
        printInstruction(instruction);
    }
    std.debug.print("    if ", .{});
    printValue(block.condition);
    std.debug.print("\n", .{});
    std.debug.print("    then {d}\n", .{block.then_block});
    std.debug.print("    else {d}\n", .{block.else_block});
}

fn printInstruction(instruction: Instruction) void {
    switch (instruction) {
        .NoOp => {},
        .Assignment => |assignment| {
            std.debug.print("    ", .{});
            printVariable(assignment.variable);
            std.debug.print(" = ", .{});
            printAssignValue(assignment.rhs);
            std.debug.print("\n", .{});
        },
        .Return => |value| {
            std.debug.print("    return ", .{});
            printValue(value);
            std.debug.print("\n", .{});
        },
        .Store => |store| {
            std.debug.print("    store ", .{});
            printValue(store.value);
            std.debug.print(" to {s}", .{store.name});
            std.debug.print("\n", .{});
        },
        .Print => |value| {
            std.debug.print("    print ", .{});
            printValue(value);
            std.debug.print("\n", .{});
        },
    }
}

fn printPhiValue(phi_value: PhiValue) void {
    printValue(phi_value.value);
    std.debug.print(" from {d}", .{phi_value.block});
}

fn printAssignValue(value: AssignValue) void {
    switch (value) {
        .BinOp => |binop| {
            printValue(binop.lhs);
            std.debug.print(" {s} ", .{@tagName(binop.op)});
            printValue(binop.rhs);
        },
        .Phi => |phi| {
            std.debug.print("Phi(", .{});
            for (phi.values.items) |w| {
                printPhiValue(w);
                std.debug.print(", ", .{});
            }
            std.debug.print(")", .{});
        },
        .FunctionCall => |function_call| {
            std.debug.print("{s}(", .{function_call.name});
            for (function_call.args.items) |arg| {
                printValue(arg);
                std.debug.print(", ", .{});
            }
            std.debug.print(")", .{});
        },
        .FunctionArg => |function_arg| {
            std.debug.print("arg {d}", .{function_arg});
        },
        .ArrayRead => |array_read| {
            printVariable(array_read.array);
            std.debug.print("[", .{});
            printValue(array_read.idx);
            std.debug.print("]", .{});
        },
        .ArrayWrite => |array_write| {
            printVariable(array_write.array);
            std.debug.print("[", .{});
            printValue(array_write.idx);
            std.debug.print("] = ", .{});
            printValue(array_write.value);
        },
        .Load => |name| {
            std.debug.print("load {s}", .{name});
        },
        .ListValue => |list| {
            std.debug.print("[", .{});
            for (list.items) |w| {
                printValue(w);
                std.debug.print(", ", .{});
            }
            std.debug.print("]", .{});
        },
        .Not => |w| {
            std.debug.print("!", .{});
            printValue(w);
        },
        .Unary => |w| {
            std.debug.print("-", .{});
            printValue(w);
        },
        .Value => |w| {
            printValue(w);
        },
    }
}

fn printValue(value: Value) void {
    switch (value) {
        .Const => |cnst| {
            switch (cnst) {
                .boolean => |boolean| {
                    std.debug.print("{}", .{boolean});
                },
                .int => |int| {
                    std.debug.print("{}", .{int});
                },
                .string => |string| {
                    std.debug.print("{s}", .{string});
                },
                .none => {
                    std.debug.print("None", .{});
                },
            }
        },
        .Var => |variable| {
            printVariable(variable);
        },
    }
}

fn printVariable(variable: Variable) void {
    std.debug.print("{s}_{d}", .{ variable.base, variable.version });
}
