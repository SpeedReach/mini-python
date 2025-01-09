const ssa = @import("../ssa/ssa.zig");
const std = @import("std");

pub const Error = error{
    //eg trying to add a string to a number
    DifferentTypes,
    //eg trying to add booleans
    NotSupported,
};

/// Returns true if the program was modified.
pub fn apply(allocator: std.mem.Allocator, program: *ssa.Program) !bool {
    var modified = false;
    var func_it = program.functions.iterator();
    while (func_it.next()) |entry| {
        if (try applyContext(allocator, entry.value_ptr)) {
            modified = true;
        }
    }
    if (try applyContext(allocator, &program.main)) {
        modified = true;
    }
    return modified;
}

fn applyContext(allocator: std.mem.Allocator, context: *ssa.FunctionContext) !bool {
    var const_vars = std.StringHashMap(ssa.Const).init(allocator);
    defer const_vars.deinit();

    var global_modified = false;
    var modified = false;
    while (true) {
        modified = false;

        var block_it = context.blocks.iterator();
        while (block_it.next()) |entry| {
            const block = entry.value_ptr.*;
            switch (block.*) {
                .Decision => {
                    if (try applyInstructions(allocator, &block.*.Decision.instructions, &const_vars)) {
                        modified = true;
                        global_modified = true;
                    }
                },
                .Sequential => {
                    if (try applyInstructions(allocator, &block.*.Sequential.instructions, &const_vars)) {
                        modified = true;
                        global_modified = true;
                    }
                },
            }
        }
        if (!modified) {
            break;
        }
    }
    return global_modified;
}
fn applyInstructions(allocator: std.mem.Allocator, instructions: *std.ArrayList(ssa.Instruction), const_vars: *std.StringHashMap(ssa.Const)) !bool {
    var modified = false;
    for (0..instructions.items.len) |idx| {
        const instruction = &instructions.items[idx];
        switch (instruction.*) {
            .Assignment => {
                switch (instruction.*.Assignment.rhs) {
                    .Value => |value| {
                        switch (value) {
                            .Const => {
                                modified = true;
                                const const_val = value.Const;
                                const var_name = try getVarName(allocator, instruction.*.Assignment.variable);
                                std.debug.print("{s} added\n", .{var_name});
                                try const_vars.put(var_name, const_val);
                                instruction.* = ssa.Instruction{ .NoOp = {} };
                            },
                            .Var => {
                                const var_name = try getVarName(allocator, value.Var);
                                if (const_vars.contains(var_name)) {
                                    modified = true;
                                    const const_val = const_vars.get(var_name).?;
                                    try const_vars.put(try getVarName(allocator, instruction.*.Assignment.variable), const_val);
                                    instruction.* = ssa.Instruction{ .NoOp = {} };
                                }
                            },
                        }
                    },
                    .ArrayRead => |array_read| {
                        if (array_read.idx != .Var) {
                            continue;
                        }
                        const var_name = try getVarName(allocator, array_read.idx.Var);
                        if (const_vars.contains(var_name)) {
                            modified = true;
                            const const_val = const_vars.get(var_name).?;
                            instruction.*.Assignment.rhs.ArrayRead.idx = .{ .Const = const_val };
                        }
                    },
                    .ArrayWrite => |array_write| {
                        if (array_write.idx == .Var) {
                            const var_name = try getVarName(allocator, array_write.idx.Var);
                            if (const_vars.contains(var_name)) {
                                modified = true;
                                const const_val = const_vars.get(var_name).?;
                                instruction.*.Assignment.rhs.ArrayWrite.idx = .{ .Const = const_val };
                            }
                        }
                        if (array_write.value == .Var) {
                            const var_name = try getVarName(allocator, array_write.value.Var);
                            if (const_vars.contains(var_name)) {
                                modified = true;
                                const const_val = const_vars.get(var_name).?;
                                instruction.*.Assignment.rhs.ArrayWrite.value = .{ .Const = const_val };
                            }
                        }
                    },
                    .FunctionArg => {
                        continue;
                    },
                    .FunctionCall => |func_call| {
                        for (0..func_call.args.items.len) |arg_idx| {
                            const arg = func_call.args.items[arg_idx];
                            if (arg == .Var) {
                                const var_name = try getVarName(allocator, arg.Var);
                                if (const_vars.contains(var_name)) {
                                    modified = true;
                                    const const_val = const_vars.get(var_name).?;
                                    instruction.*.Assignment.rhs.FunctionCall.args.items[arg_idx] = .{ .Const = const_val };
                                }
                            }
                        }
                    },
                    .ListValue => |list| {
                        for (0..list.items.len) |arg_idx| {
                            const arg = list.items[arg_idx];
                            if (arg == .Var) {
                                const var_name = try getVarName(allocator, arg.Var);
                                if (const_vars.contains(var_name)) {
                                    modified = true;
                                    const const_val = const_vars.get(var_name).?;
                                    instruction.*.Assignment.rhs.ListValue.items[arg_idx] = .{ .Const = const_val };
                                }
                            }
                        }
                    },
                    .Load => {
                        continue;
                    },
                    .Not => |n| {
                        switch (n) {
                            .Const => {
                                modified = true;
                                const const_val = not(n.Const);
                                try const_vars.put(try getVarName(allocator, instruction.*.Assignment.variable), const_val);
                                instruction.* = ssa.Instruction{ .NoOp = {} };
                            },
                            .Var => {
                                const var_name = try getVarName(allocator, n.Var);
                                if (const_vars.contains(var_name)) {
                                    modified = true;
                                    const const_val = not(const_vars.get(var_name).?);
                                    try const_vars.put(try getVarName(allocator, instruction.*.Assignment.variable), const_val);
                                    instruction.* = ssa.Instruction{ .NoOp = {} };
                                }
                            },
                        }
                    },
                    .Phi => |phi| {
                        for (0..phi.values.items.len) |arg_idx| {
                            const arg: ssa.PhiValue = phi.values.items[arg_idx];
                            if (arg.value == .Var) {
                                const var_name = try getVarName(allocator, arg.value.Var);
                                if (const_vars.contains(var_name)) {
                                    std.debug.print("replacing phi value {s}_{d} with const.\n", .{ arg.value.Var.base, arg.value.Var.version });
                                    modified = true;
                                    const const_val = const_vars.get(var_name).?;
                                    instruction.*.Assignment.rhs.Phi.values.items[arg_idx].value = .{ .Const = const_val };
                                }
                            }
                        }
                    },
                    .Unary => |u| {
                        switch (u) {
                            .Const => {
                                modified = true;
                                const const_val = try unary(u.Const);
                                try const_vars.put(try getVarName(allocator, instruction.*.Assignment.variable), const_val);
                                instruction.* = ssa.Instruction{ .NoOp = {} };
                            },
                            .Var => {
                                const var_name = try getVarName(allocator, u.Var);
                                if (const_vars.contains(var_name)) {
                                    modified = true;
                                    const const_val = try unary(const_vars.get(var_name).?);
                                    try const_vars.put(try getVarName(allocator, instruction.*.Assignment.variable), const_val);
                                    instruction.* = ssa.Instruction{ .NoOp = {} };
                                }
                            },
                        }
                    },
                    .BinOp => |binOp| {
                        if (binOp.lhs == .Var) {
                            const var_name = try getVarName(allocator, binOp.lhs.Var);
                            if (const_vars.contains(var_name)) {
                                modified = true;
                                instruction.*.Assignment.rhs.BinOp.lhs = .{ .Const = const_vars.get(var_name).? };
                            }
                        }
                        if (binOp.rhs == .Var) {
                            const var_name = try getVarName(allocator, binOp.rhs.Var);
                            if (const_vars.contains(var_name)) {
                                modified = true;
                                instruction.*.Assignment.rhs.BinOp.rhs = .{ .Const = const_vars.get(var_name).? };
                            }
                        }
                        if (binOp.op == .@"and" or binOp.op == .@"or") {
                            if (instruction.*.Assignment.rhs.BinOp.lhs == .Const) {
                                const const_val = try evaluateAndOr(instruction.*.Assignment.rhs.BinOp.lhs.Const, binOp.op);
                                if (const_val != null) {
                                    try const_vars.put(try getVarName(allocator, instruction.*.Assignment.variable), const_val.?);
                                    instruction.* = ssa.Instruction{ .NoOp = {} };
                                    modified = true;
                                    continue;
                                }
                            }
                        }
                        const new_bin_op = instruction.*.Assignment.rhs.BinOp;
                        if (new_bin_op.lhs == .Const and new_bin_op.rhs == .Const) {
                            const const_val = try evaluateBinOp(allocator, new_bin_op.lhs.Const, new_bin_op.rhs.Const, new_bin_op.op);
                            try const_vars.put(try getVarName(allocator, instruction.*.Assignment.variable), const_val);
                            instruction.* = ssa.Instruction{ .NoOp = {} };
                            modified = true;
                        }
                    },
                }
            },
            .Return => {
                if (instruction.*.Return == .Var) {
                    const var_name = try getVarName(allocator, instruction.*.Return.Var);
                    if (const_vars.contains(var_name)) {
                        modified = true;
                        instruction.*.Return = .{ .Const = const_vars.get(var_name).? };
                    }
                }
            },
            .NoOp => {},
            .Print => {
                if (instruction.*.Print == .Var) {
                    const var_name = try getVarName(allocator, instruction.*.Print.Var);
                    if (const_vars.contains(var_name)) {
                        modified = true;
                        instruction.*.Print = .{ .Const = const_vars.get(var_name).? };
                    }
                }
            },
            .Store => |store| {
                if (store.value == .Var) {
                    const var_name = try getVarName(allocator, store.value.Var);
                    if (const_vars.contains(var_name)) {
                        modified = true;
                        instruction.*.Store.value = .{ .Const = const_vars.get(var_name).? };
                    }
                }
            },
        }
    }
    return modified;
}

fn getVarName(allocator: std.mem.Allocator, variable: ssa.Variable) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}_{d}", .{ variable.base, variable.version });
}

const evalBool = ssa.isBool;

const not = ssa.not;
const unary = ssa.unary;

// Quick and , or folding
fn evaluateAndOr(c1: ssa.Const, op: ssa.BinOp) !?ssa.Const {
    const a = evalBool(c1);
    if (op == .@"and") {
        if (!a) {
            return ssa.Const{ .boolean = false };
        }
        return null;
    } else if (op == .@"or") {
        if (a) {
            return ssa.Const{ .boolean = true };
        }
        return null;
    }
    return null;
}

/// In cmp, bool is considered as int
fn evaluateBinOp(allocator: std.mem.Allocator, c1: ssa.Const, c2: ssa.Const, binOp: ssa.BinOp) !ssa.Const {
    switch (binOp) {
        .@"and" => {
            const a = evalBool(c1);
            if (!a) {
                return ssa.Const{ .boolean = false };
            }
            return ssa.Const{ .boolean = a and evalBool(c2) };
        },
        .@"or" => {
            const a = evalBool(c1);
            if (a) {
                return ssa.Const{ .boolean = true };
            }
            return ssa.Const{ .boolean = a or evalBool(c2) };
        },
        .add => {
            if (c1 == .int and c2 == .int) {
                return ssa.Const{ .int = c1.int + c2.int };
            }
            if (c1 == .string and c2 == .string) {
                return ssa.Const{ .string = try std.fmt.allocPrint(allocator, "{s}{s}", .{ c1.string, c2.string }) };
            }
            return Error.NotSupported;
        },
        .div => {
            if (c1 == .int and c2 == .int) {
                return ssa.Const{ .int = @divTrunc(c1.int, c2.int) };
            }
            return Error.NotSupported;
        },
        .eq => {
            return ssa.Const{ .boolean = equal(c1, c2) };
        },
        .ge => {
            const compare = try cmp(c1, c2);
            return ssa.Const{ .boolean = compare >= 0 };
        },
        .gt => {
            const compare = try cmp(c1, c2);
            return ssa.Const{ .boolean = compare > 0 };
        },
        .le => {
            const compare = try cmp(c1, c2);
            return ssa.Const{ .boolean = compare <= 0 };
        },
        .lt => {
            const compare = try cmp(c1, c2);
            return ssa.Const{ .boolean = compare < 0 };
        },
        .mod => {
            if (c1 == .int and c2 == .int) {
                return ssa.Const{ .int = @mod(c1.int, c2.int) };
            }
            return Error.NotSupported;
        },
        .mul => {
            if (c1 == .int and c2 == .int) {
                return ssa.Const{ .int = c1.int * c2.int };
            }
            return Error.NotSupported;
        },
        .ne => {
            return ssa.Const{ .boolean = !equal(c1, c2) };
        },
        .sub => {
            if (c1 == .int and c2 == .int) {
                return ssa.Const{ .int = c1.int - c2.int };
            }
            return Error.NotSupported;
        },
    }
}

const cmp = ssa.cmp;
const equal = ssa.equal;
