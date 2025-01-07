const ssa = @import("../ssa/ssa.zig");
const std = @import("std");
const x64 = @import("x86_64.zig");

const Indent = "    ";
const exitBlockId = std.math.maxInt(u32);
const VarName = []const u8;
const Allocator = std.mem.Allocator;
const uuid = @import("../utils/uuid.zig");

pub const Error = error{
    ArrIdxNotInt,
    Phi,
    NotSupported,
};

pub fn generate(writer: std.io.AnyWriter, program: ssa.Program) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var const_strings = std.StringHashMap([]const u8).init(allocator);
    defer const_strings.deinit();
    var it = program.const_strings.keyIterator();
    var i: i64 = 0;
    while (it.next()) |entry| {
        const key = entry.*;
        const value = try std.fmt.allocPrint(allocator, "str_{d}", .{i});
        try const_strings.put(key, value);
        i += 1;
    }

    try writeData(writer, const_strings);
    try writeBss(writer, program.global_vars);
    try writeBuiltin(writer);
    try writeContext(allocator, writer, program.main);
    try writeExit(writer);

    var func_it = program.functions.iterator();
    while (func_it.next()) |entry| {
        try writeContext(allocator, writer, entry.value_ptr.*);
        try writer.print("{s}movq   %rbp, %rsp\n", .{Indent});
        try writer.print("{s}popq   %rbp\n", .{Indent});
        try writer.print("{s}ret\n", .{Indent});
    }
}

fn writeExit(writer: std.io.AnyWriter) !void {
    try writer.print("{s}andq   $-16, %rsp\n", .{Indent});
    try writer.print("{s}movq   (stdout), %rdi\n", .{Indent});
    try writer.print("{s}call   fflush\n", .{Indent});
    try writer.print("{s}movq    $60, %rax\n", .{Indent});
    try writer.print("{s}xorq    %rdi, %rdi\n", .{Indent});
    try writer.print("{s}syscall\n", .{Indent});
}

fn writeContext(allocator: std.mem.Allocator, writer: std.io.AnyWriter, context: ssa.FunctionContext) !void {
    var rbp_offsets = std.StringHashMap(i64).init(allocator);
    defer rbp_offsets.deinit();
    var declared_vars = try findDeclaredVars(allocator, context);
    defer declared_vars.deinit();
    var var_it = declared_vars.iterator();

    var i: i64 = 0;
    while (var_it.next()) |declared_var| {
        i -= 8;
        try rbp_offsets.put(declared_var.key_ptr.*, i);
    }

    try writer.print("{s}:\n", .{context.name});
    const alloc_size = 8 * declared_vars.count();
    try writer.print("{s}pushq  %rbp\n", .{Indent});
    try writer.print("{s}movq    %rsp, %rbp\n", .{Indent});
    try writer.print("{s}subq    ${d}, %rsp\n", .{ Indent, alloc_size });
    for (0..(context.blocks.count() - 1)) |id| {
        const block = context.blocks.get(@intCast(id)).?;
        try writeBlock(allocator, writer, block.*, &context.blocks, &rbp_offsets);
    }
    const exit_block = context.blocks.get(std.math.maxInt(u32)).?;
    try writeBlock(allocator, writer, exit_block.*, &context.blocks, &rbp_offsets);
}

fn findDeclaredVars(allocator: std.mem.Allocator, context: ssa.FunctionContext) !std.StringHashMap(void) {
    var declared_vars = std.StringHashMap(void).init(allocator);
    var it = context.blocks.valueIterator();
    while (it.next()) |block| {
        switch (block.*.*) {
            .Decision => try findBlockDeclaredVars(allocator, &block.*.Decision.instructions, &declared_vars),
            .Sequential => try findBlockDeclaredVars(allocator, &block.*.Sequential.instructions, &declared_vars),
        }
    }
    return declared_vars;
}

fn findBlockDeclaredVars(allocator: std.mem.Allocator, insts: *const std.ArrayList(ssa.Instruction), dest: *std.StringHashMap(void)) !void {
    for (insts.items) |inst| {
        switch (inst) {
            .Assignment => {
                try dest.put(try getVarName(allocator, inst.Assignment.variable), void{});
            },
            else => {},
        }
    }
}

fn getVarName(allocator: std.mem.Allocator, variable: ssa.Variable) !VarName {
    return try std.fmt.allocPrint(allocator, "{s}_{d}", .{ variable.base, variable.version });
}

/// put 0 or 1 in %rax
fn writeIsBool(allocator: std.mem.Allocator, writer: std.io.AnyWriter, value: ssa.Value, rbp_offset: *const std.StringHashMap(i64)) !void {
    switch (value) {
        .Const => |cnst| {
            const boolean = ssa.isBool(cnst);
            if (boolean) {
                try writer.print("{s}movq    $1, %rax\n", .{Indent});
            } else {
                try writer.print("{s}movq    $0, %rax\n", .{Indent});
            }
        },
        .Var => |variable| {
            const varname = try getVarName(allocator, variable);
            defer allocator.free(varname);
            const offset = rbp_offset.get(varname).?;
            try writer.print("{s}movq   {d}(%rbp), %rax\n", .{ Indent, offset });
            try writer.print("{s}pushq  %rax\n", .{Indent});
            try writer.print("{s}call   is_bool\n", .{Indent});
            try writer.print("{s}addq  $8, %rsp\n", .{Indent});
        },
    }
}

fn writeBlock(allocator: std.mem.Allocator, writer: std.io.AnyWriter, block: ssa.Block, blocks: *const std.AutoHashMap(u32, *ssa.Block), rbp_offset: *const std.StringHashMap(i64)) !void {
    std.debug.print("block name: {s}\n", .{getBlockName(&block)});
    switch (block) {
        .Decision => {
            try writer.print("{s}:\n", .{block.Decision.name});
            try writeInstructions(allocator, writer, block.Decision.instructions, rbp_offset);
            //Check condition is true then jump
            try writeIsBool(allocator, writer, block.Decision.condition, rbp_offset);
            try writer.print("{s}cmpq    $1, %rax\n", .{Indent});
            const then_block = blocks.get(block.Decision.then_block).?;
            const else_block = blocks.get(block.Decision.else_block).?;
            try writer.print("{s}je      {s}\n", .{ Indent, getBlockName(then_block) });
            try writer.print("{s}jmp     {s}\n", .{ Indent, getBlockName(else_block) });
        },
        .Sequential => {
            try writer.print("{s}:\n", .{block.Sequential.name});
            try writeInstructions(allocator, writer, block.Sequential.instructions, rbp_offset);
            if (block.Sequential.id != exitBlockId) {
                const nextBlockName = getBlockName(blocks.get(block.Sequential.successor).?);
                try writer.print("{s}jmp {s}\n", .{ Indent, nextBlockName });
            }
        },
    }
}

fn writeInstructions(allocator: Allocator, w: std.io.AnyWriter, insts: std.ArrayList(ssa.Instruction), rbp_offsets: *const std.StringHashMap(i64)) !void {
    for (insts.items) |inst| {
        switch (inst) {
            .Assignment => {
                try writeAssignment(allocator, w, inst.Assignment, rbp_offsets);
            },
            .Print => {
                switch (inst.Print) {
                    .Const => {
                        try writeConst(w, inst.Print.Const);
                        try w.print("{s}pushq   %rax\n", .{Indent});
                    },
                    .Var => {
                        const varname = try getVarName(allocator, inst.Print.Var);
                        defer allocator.free(varname);
                        const offset = rbp_offsets.get(varname).?;
                        try w.print("{s}movq    {d}(%rbp), %rax\n", .{ Indent, offset });
                        try w.print("{s}pushq   %rax\n", .{Indent});
                    },
                }
                try w.print("{s}print\n", .{Indent});
            },
            .Return => {
                switch (inst.Return) {
                    .Const => {
                        try writeConst(w, inst.Return.Const);
                    },
                    .Var => {
                        const varname = try getVarName(allocator, inst.Return.Var);
                        defer allocator.free(varname);
                        const offset = rbp_offsets.get(varname).?;
                        try w.print("{s}movq    {d}(%rbp), %rax\n", .{ Indent, offset });
                    },
                }
                try w.print("{s}movq    %rbp, %rsp\n", .{Indent});
                try w.print("{s}popq    %rbp\n", .{Indent});
                try w.print("{s}ret\n", .{Indent});
            },
            .Store => |store| {
                switch (store.value) {
                    .Const => {
                        try writeConst(w, store.value.Const);
                        try w.print("{s}movq    %rax, ({s})\n", .{ Indent, store.name });
                    },
                    .Var => {
                        const varname = try getVarName(allocator, store.value.Var);
                        defer allocator.free(varname);
                        const offset = rbp_offsets.get(varname).?;
                        try w.print("{s}movq    {d}(%rbp), %rax\n", .{ Indent, offset });
                        try w.print("{s}movq    %rax, ({s})\n", .{ Indent, store.name });
                    },
                }
            },
            .NoOp => {},
        }
    }
}

/// Allocates memory on the heap for the constant
/// The pointer to the memory is stored in %rax
fn writeConst(w: std.io.AnyWriter, cnst: ssa.Const) !void {
    switch (cnst) {
        .none => {
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}movq    $0, (%rax)\n", .{Indent});
            try w.print("{s}movq    $0, 8(%rax)\n", .{Indent});
        },
        .boolean => {
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}movq    $1, (%rax)\n", .{Indent});
            try w.print("{s}movq    ${d}, 8(%rax)\n", .{ Indent, @as(i64, if (cnst.boolean) 1 else 0) });
        },
        .int => {
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}movq    $2, (%rax)\n", .{Indent});
            try w.print("{s}movq    ${d}, 8(%rax)\n", .{ Indent, cnst.int });
        },
        .string => {
            const length = cnst.string.len;
            try w.print("{s}malloc  ${d}\n", .{ Indent, length + 16 });
            try w.print("{s}movq    $3, (%rax)\n", .{Indent});
            try w.print("{s}movq    ${d}, 8(%rax)\n", .{ Indent, length });
            for (0..length) |i| {
                try w.print("{s}movb    ${d}, {d}(%rax)\n", .{ Indent, cnst.string[i], 16 + i });
            }
        },
    }
}

fn writeAssignment(allocator: Allocator, w: std.io.AnyWriter, assignment: ssa.Assignment, rbp_offsets: *const std.StringHashMap(i64)) !void {
    const assign_var = try getVarName(allocator, assignment.variable);
    defer allocator.free(assign_var);
    const assign_offset = rbp_offsets.get(assign_var).?;
    switch (assignment.rhs) {
        .BinOp => {
            try writeBinOp(allocator, w, assignment.rhs.BinOp, rbp_offsets);
            try w.print("{s}movq    %rax,       {d}(%rbp)\n", .{ Indent, assign_offset });
        },
        .Value => |value| {
            switch (value) {
                .Const => {
                    try writeConst(w, value.Const);
                    try w.print("{s}movq    %rax,       {d}(%rbp)\n", .{ Indent, assign_offset });
                },
                .Var => {
                    const varname = try getVarName(allocator, value.Var);
                    defer allocator.free(varname);
                    std.debug.print("var name: {s}\n", .{varname});
                    const offset = rbp_offsets.get(varname).?;
                    try w.print("{s}movq    {d}(%rbp),  %rax     \n", .{ Indent, offset });
                    try w.print("{s}movq    %rax,       {d}(%rbp)\n", .{ Indent, assign_offset });
                },
            }
        },
        .FunctionArg => |func_arg| {
            try w.print("{s}movq    {d}(%rbp),  %rax\n", .{ Indent, 16 + 8 * func_arg });
            try w.print("{s}movq    %rax,       {d}(%rbp)\n", .{ Indent, assign_offset });
        },
        .FunctionCall => |function_call| {
            for (0..function_call.args.items.len) |idx| {
                const arg = function_call.args.items[function_call.args.items.len - idx - 1];
                switch (arg) {
                    .Var => {
                        const varname = try getVarName(allocator, arg.Var);
                        defer allocator.free(varname);
                        const offset = rbp_offsets.get(varname).?;
                        try w.print("{s}movq    {d}(%rbp),  %rax\n", .{ Indent, offset });
                        try w.print("{s}pushq   %rax\n", .{Indent});
                    },
                    .Const => {
                        try writeConst(w, arg.Const);
                        try w.print("{s}pushq   %rax\n", .{Indent});
                    },
                }
            }
            try w.print("{s}call    __{s}\n", .{ Indent, function_call.name });
            try w.print("{s}addq    ${d}, %rsp\n", .{ Indent, function_call.args.items.len * 8 });
            try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
        },
        .Load => |load| {
            try w.print("{s}movq    ({s}), %rax\n", .{ Indent, load });
            try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
        },
        .ListValue => |list| {
            try w.writeAll("\n");
            try w.print("{s}malloc  ${d}            \n", .{ Indent, 16 + list.items.len * 8 });
            try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
            try w.print("{s}pushq   %rax           \n", .{Indent});
            try w.print("{s}movq    $4,     (%rax)\n", .{Indent});
            try w.print("{s}movq    ${d},   8(%rax)\n", .{ Indent, list.items.len });
            var i: u32 = 1;
            for (list.items) |item| {
                i += 1;
                switch (item) {
                    .Const => {
                        try writeConst(w, item.Const);
                        try w.print("{s}movq    (%rsp), %rbx\n", .{Indent});
                        try w.print("{s}movq    %rax,   {d}(%rbx)\n", .{ Indent, i * 8 });
                    },
                    .Var => {
                        const varname = try getVarName(allocator, item.Var);
                        defer allocator.free(varname);
                        const offset = rbp_offsets.get(varname).?;
                        try w.print("{s}movq    {d}(%rbp),  %rax \n", .{ Indent, offset });
                        try w.print("{s}movq    (%rsp), %rbx\n", .{Indent});
                        try w.print("{s}movq    %rax,   {d}(%rbx)\n", .{ Indent, i * 8 });
                    },
                }
            }
            try w.print("{s}popq    %rax\n", .{Indent});
            try w.writeAll("\n");
        },
        .ArrayRead => |arr_read| {
            const arr_varname = try getVarName(allocator, arr_read.array);
            defer allocator.free(arr_varname);
            const arr_offset = rbp_offsets.get(arr_varname).?;
            try w.print("{s}movq    {d}(%rbp),  %rax\n", .{ Indent, arr_offset });
            try w.print("{s}pushq   %rax\n", .{Indent});
            try w.print("{s}movq    (%rax), %rax\n", .{Indent});
            try w.print("{s}cmpq    $4, %rax\n", .{Indent});
            try w.print("{s}jne     runtime_panic\n", .{Indent});

            // Move the index to %rbx
            switch (arr_read.idx) {
                .Const => {
                    if (arr_read.idx.Const != .int) {
                        return Error.ArrIdxNotInt;
                    }
                    try w.print("{s}movq    ${d}, %rbx\n", .{ Indent, arr_read.idx.Const.int });
                },
                .Var => {
                    const idx_varname = try getVarName(allocator, arr_read.idx.Var);
                    defer allocator.free(idx_varname);
                    const idx_offset = rbp_offsets.get(idx_varname).?;
                    // Check if the variable is an integer
                    try w.print("{s}movq    {d}(%rbp), %rbx\n", .{ Indent, idx_offset });
                    try w.print("{s}movq    (%rbx), %rax\n", .{Indent});
                    try w.print("{s}cmpq    $2, %rax\n", .{Indent});
                    try w.print("{s}jne     runtime_panic\n", .{Indent});
                    try w.print("{s}movq    8(%rbx), %rbx\n", .{Indent});
                },
            }
            //Check if index is within bounds
            try w.print("{s}popq    %rax\n", .{Indent});
            try w.print("{s}movq    8(%rax), %rcx\n", .{Indent});
            try w.print("{s}cmpq    %rcx, %rbx\n", .{Indent});
            try w.print("{s}jge     runtime_panic\n", .{Indent});
            //Add index * 8 to the array pointer
            try w.print("{s}imul    $8, %rbx\n", .{Indent});
            try w.print("{s}addq    %rbx, %rax\n", .{Indent});
            try w.print("{s}movq   16(%rax), %rax\n", .{Indent});
            //Move the value to assign_offset
            try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
        },
        .ArrayWrite => |arr_write| {
            //TODO
            const arr_varname = try getVarName(allocator, arr_write.array);
            defer allocator.free(arr_varname);
            const arr_offset = rbp_offsets.get(arr_varname).?;
            try w.print("{s}movq    {d}(%rbp),  %rax\n", .{ Indent, arr_offset });
            try w.print("{s}pushq   %rax\n", .{Indent});
            try w.print("{s}movq    (%rax), %rax\n", .{Indent});
            try w.print("{s}cmpq    $4, %rax\n", .{Indent});
            try w.print("{s}jne     runtime_panic\n", .{Indent});

            // Move the index to %rbx
            switch (arr_write.idx) {
                .Const => {
                    if (arr_write.idx.Const != .int) {
                        return Error.ArrIdxNotInt;
                    }
                    try w.print("{s}movq    ${d}, %rbx\n", .{ Indent, arr_write.idx.Const.int });
                },
                .Var => {
                    const idx_varname = try getVarName(allocator, arr_write.idx.Var);
                    defer allocator.free(idx_varname);
                    const idx_offset = rbp_offsets.get(idx_varname).?;
                    // Check if the variable is an integer
                    try w.print("{s}movq    {d}(%rbp), %rbx\n", .{ Indent, idx_offset });
                    try w.print("{s}movq    (%rbx), %rax\n", .{Indent});
                    try w.print("{s}cmpq    $2, %rax\n", .{Indent});
                    try w.print("{s}jne     runtime_panic\n", .{Indent});
                    try w.print("{s}movq    8(%rbx), %rbx\n", .{Indent});
                },
            }
            //Check if index is within bounds
            try w.print("{s}popq    %rax\n", .{Indent});
            try w.print("{s}movq    8(%rax), %rcx\n", .{Indent});
            try w.print("{s}cmpq    %rcx, %rbx\n", .{Indent});
            try w.print("{s}jge     runtime_panic\n", .{Indent});
            //Add index * 8 to the array pointer
            try w.print("{s}imul    $8, %rbx\n", .{Indent});
            try w.print("{s}addq    %rbx, %rax\n", .{Indent});
            try w.print("{s}addq    $16, %rax\n", .{Indent});
            try w.print("{s}pushq   %rax\n", .{Indent});

            switch (arr_write.value) {
                .Const => {
                    try writeConst(w, arr_write.value.Const);
                },
                .Var => {
                    const varname = try getVarName(allocator, arr_write.value.Var);
                    defer allocator.free(varname);
                    const offset = rbp_offsets.get(varname).?;
                    try w.print("{s}movq    {d}(%rbp), %rax\n", .{ Indent, offset });
                },
            }
            try w.print("{s}popq   %rbx\n", .{Indent});
            try w.print("{s}movq    %rax, (%rbx)\n", .{Indent});

            try w.print("{s}movq    {d}(%rbp),  %rax\n", .{ Indent, arr_offset });
            try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
        },
        .Not => |not| {
            switch (not) {
                .Const => {
                    try writeConst(w, ssa.not(not.Const));
                    try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
                },
                .Var => {
                    const varname = try getVarName(allocator, not.Var);
                    defer allocator.free(varname);
                    const offset = rbp_offsets.get(varname).?;
                    try w.print("{s}movq    {d}(%rbp), %rax\n", .{ Indent, offset });
                    try w.print("{s}pushq   %rax\n", .{Indent});
                    try w.print("{s}call    not\n", .{Indent});
                    try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
                    try w.print("{s}addq    $8, %rsp\n", .{Indent});
                },
            }
        },
        .Unary => |unary| {
            switch (unary) {
                .Const => {
                    try writeConst(w, try ssa.unary(unary.Const));
                },
                .Var => {
                    const varname = try getVarName(allocator, unary.Var);
                    defer allocator.free(varname);
                    const offset = rbp_offsets.get(varname).?;
                    try w.print("{s}movq    {d}(%rbp),  %rax\n", .{ Indent, offset });
                    try w.print("{s}movq    (%rax),     %rbx\n", .{Indent});
                    try w.print("{s}cmpq    $2, %rbx        \n", .{Indent});
                    try w.print("{s}jne runtime_panic       \n", .{Indent});
                    try w.print("{s}movq    8(%rax),    %rax\n", .{Indent});
                    try w.print("{s}imul    $-1,        %rax\n", .{Indent});
                    try w.print("{s}pushq   %rax\n", .{Indent});
                    try w.print("{s}malloc  $16\n", .{Indent});
                    try w.print("{s}movq    $2, (%rax)\n", .{Indent});
                    try w.print("{s}popq    %r9\n", .{Indent});
                    try w.print("{s}movq    %r9, 8(%rax)\n", .{Indent});
                    try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
                },
            }
        },
        .Phi => {
            return Error.Phi;
        },
    }
}

var tmp_branch_index: u32 = 0;

fn getRandBranchName(allocator: Allocator) ![]const u8 {
    const n = try std.fmt.allocPrint(allocator, "branch_{d}", .{tmp_branch_index});
    tmp_branch_index += 1;
    return n;
}

///Result should be in %rax, as a pointer to the heap allocated memory
fn writeBinOp(allocator: Allocator, w: std.io.AnyWriter, bin_op: ssa.BinOpExpr, rbp_offsets: *const std.StringHashMap(i64)) !void {
    switch (bin_op.op) {
        .add => {
            try writeVal(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeVal(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}popq    %rdi\n", .{Indent});
            try w.print("{s}movq    %rax, %rsi\n", .{Indent});
            try w.print("{s}call    _builtin_add\n", .{Indent});
        },
        .@"and" => {
            try writeIsBool(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeIsBool(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r8\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}andq    %r8, %r9\n", .{Indent});
            try w.print("{s}movq    $1, (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .@"or" => {
            try writeIsBool(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeIsBool(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r8\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}orq    %r8, %r9\n", .{Indent});
            try w.print("{s}movq    $1, (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .sub => {
            try writeInt(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeInt(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}popq    %rbx\n", .{Indent});
            try w.print("{s}subq    %rbx, %rax\n", .{Indent});
            try w.print("{s}pushq   %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $2,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .div => {
            try writeInt(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeInt(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}xorq    %rdx,   %rdx\n", .{Indent});
            try w.print("{s}popq    %rbx\n", .{Indent});
            try w.print("{s}idivq   %rbx\n", .{Indent});
            try w.print("{s}pushq   %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $2,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .mod => {
            try writeInt(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeInt(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}xorq    %rdx,   %rdx\n", .{Indent});
            try w.print("{s}popq    %rbx\n", .{Indent});
            try w.print("{s}idivq   %rbx\n", .{Indent});
            try w.print("{s}movq    %rdx,   %rax\n", .{Indent});
            // Remainder is in %rdx
            try w.print("{s}pushq   %rdx\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $2,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .mul => {
            try writeInt(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeInt(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}popq    %rbx\n", .{Indent});
            try w.print("{s}imulq   %rbx, %rax\n", .{Indent});
            try w.print("{s}pushq   %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $2,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .gt => {
            try writeVal(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeVal(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}popq    %rdi\n", .{Indent});
            try w.print("{s}movq    %rax, %rsi\n", .{Indent});
            try w.print("{s}call    _builtin_cmp\n", .{Indent});
            try w.print("{s}cmpq    $1, %rax\n", .{Indent});
            const gt_label = try getRandBranchName(allocator);
            const end_label = try getRandBranchName(allocator);
            try w.print("{s}je      {s}\n", .{ Indent, gt_label });
            try w.print("{s}movq    $0, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{gt_label});
            try w.print("{s}movq    $1, %rax\n", .{Indent});
            try w.print("{s}pushq  %rax\n", .{Indent});
            try w.print("{s}:\n", .{end_label});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $1,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .ge => {
            try writeVal(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeVal(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}popq    %rdi\n", .{Indent});
            try w.print("{s}movq    %rax, %rsi\n", .{Indent});
            try w.print("{s}call    _builtin_cmp\n", .{Indent});
            try w.print("{s}cmpq    $-1, %rax\n", .{Indent});
            const ge_label = try getRandBranchName(allocator);
            const else_label = try getRandBranchName(allocator);
            const end_label = try getRandBranchName(allocator);
            try w.print("{s}je      {s}\n", .{ Indent, else_label });
            try w.print("{s}jmp {s}\n", .{ Indent, ge_label });
            try w.print("{s}:\n", .{ge_label});
            try w.print("{s}movq    $1, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{else_label});
            try w.print("{s}movq    $0, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{end_label});
            try w.print("{s}pushq  %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $1,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .eq => {
            try writeVal(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeVal(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}popq    %rdi\n", .{Indent});
            try w.print("{s}movq    %rax, %rsi\n", .{Indent});
            try w.print("{s}call    _builtin_cmp\n", .{Indent});
            try w.print("{s}cmpq    $0, %rax\n", .{Indent});
            const eq_label = try getRandBranchName(allocator);
            const else_label = try getRandBranchName(allocator);
            const end_label = try getRandBranchName(allocator);
            try w.print("{s}je      {s}\n", .{ Indent, eq_label });
            try w.print("{s}jmp {s}\n", .{ Indent, else_label });
            try w.print("{s}:\n", .{eq_label});
            try w.print("{s}movq    $1, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{else_label});
            try w.print("{s}movq    $0, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{end_label});
            try w.print("{s}pushq  %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $1,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .ne => {
            try writeVal(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeVal(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}popq    %rdi\n", .{Indent});
            try w.print("{s}movq    %rax, %rsi\n", .{Indent});
            try w.print("{s}call    _builtin_cmp\n", .{Indent});
            try w.print("{s}cmpq    $0, %rax\n", .{Indent});
            const ne_label = try getRandBranchName(allocator);
            const else_label = try getRandBranchName(allocator);
            const end_label = try getRandBranchName(allocator);
            try w.print("{s}je      {s}\n", .{ Indent, ne_label });
            try w.print("{s}jmp {s}\n", .{ Indent, else_label });
            try w.print("{s}:\n", .{ne_label});
            try w.print("{s}movq    $0, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{else_label});
            try w.print("{s}movq    $1, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{end_label});
            try w.print("{s}pushq  %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $1,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .le => {
            try writeVal(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeVal(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}popq    %rdi\n", .{Indent});
            try w.print("{s}movq    %rax, %rsi\n", .{Indent});
            try w.print("{s}call    _builtin_cmp\n", .{Indent});
            try w.print("{s}cmpq    $1, %rax\n", .{Indent});
            const gt_label = try getRandBranchName(allocator);
            const else_label = try getRandBranchName(allocator);
            const end_label = try getRandBranchName(allocator);
            try w.print("{s}je      {s}\n", .{ Indent, gt_label });
            try w.print("{s}jmp {s}\n", .{ Indent, else_label });
            try w.print("{s}:\n", .{gt_label});
            try w.print("{s}movq    $0, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{else_label});
            try w.print("{s}movq    $1, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{end_label});
            try w.print("{s}pushq  %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $1,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
        .lt => {
            try writeVal(allocator, w, bin_op.lhs, rbp_offsets);
            try w.print("{s}pushq   %rax\n", .{Indent});
            try writeVal(allocator, w, bin_op.rhs, rbp_offsets);
            try w.print("{s}popq    %rdi\n", .{Indent});
            try w.print("{s}movq    %rax, %rsi\n", .{Indent});
            try w.print("{s}call    _builtin_cmp\n", .{Indent});
            try w.print("{s}cmpq    $-1, %rax\n", .{Indent});
            const lt_label = try getRandBranchName(allocator);
            const else_label = try getRandBranchName(allocator);
            const end_label = try getRandBranchName(allocator);
            try w.print("{s}je      {s}\n", .{ Indent, lt_label });
            try w.print("{s}jmp {s}\n", .{ Indent, else_label });
            try w.print("{s}:\n", .{lt_label});
            try w.print("{s}movq    $1, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{else_label});
            try w.print("{s}movq    $0, %rax\n", .{Indent});
            try w.print("{s}jmp     {s}\n", .{ Indent, end_label });
            try w.print("{s}:\n", .{end_label});
            try w.print("{s}pushq  %rax\n", .{Indent});
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}popq    %r9\n", .{Indent});
            try w.print("{s}movq    $1,     (%rax)\n", .{Indent});
            try w.print("{s}movq    %r9,    8(%rax)\n", .{Indent});
        },
    }
}

/// Write value and store the pointer to the heap allocated memory in %rax
fn writeVal(allocator: std.mem.Allocator, w: std.io.AnyWriter, value: ssa.Value, rbp_offsets: *const std.StringHashMap(i64)) !void {
    switch (value) {
        .Const => {
            try writeConst(w, value.Const);
        },
        .Var => {
            const varname = try getVarName(allocator, value.Var);
            defer allocator.free(varname);
            std.debug.print("varname: {s}\n", .{varname});
            const offset = rbp_offsets.get(varname).?;
            try w.print("{s}movq    {d}(%rbp), %rax\n", .{ Indent, offset });
        },
    }
}

/// Write int value to %rax
fn writeInt(allocator: std.mem.Allocator, writer: std.io.AnyWriter, value: ssa.Value, rbp_offset: *const std.StringHashMap(i64)) !void {
    switch (value) {
        .Const => {
            if (value.Const != .int) {
                return Error.NotSupported;
            }
            try writer.print("{s}movq    ${d}, %rax\n", .{ Indent, value.Const.int });
        },
        .Var => {
            const varname = try getVarName(allocator, value.Var);
            defer allocator.free(varname);
            const offset = rbp_offset.get(varname).?;
            try writer.print("{s}movq    {d}(%rbp), %rax\n", .{ Indent, offset });
            try writer.print("{s}movq    (%rax), %rcx\n", .{Indent});
            try writer.print("{s}cmpq    $2, %rcx\n", .{Indent});
            try writer.print("{s}jne     runtime_panic\n", .{Indent});
            try writer.print("{s}movq    8(%rax), %rax\n", .{Indent});
        },
    }
}

fn writeBss(writer: std.io.AnyWriter, global_vars: std.StringHashMap(void)) !void {
    if (global_vars.count() == 0) {
        return;
    }
    try writer.writeAll(".bss\n");
    var it = global_vars.iterator();
    while (it.next()) |gv| {
        try writer.writeAll(Indent);
        try writer.print("{s}: .zero 8\n", .{gv.key_ptr.*});
    }
}

const builtin = @import("./builtin.zig").builtin;
fn writeBuiltin(writer: std.io.AnyWriter) !void {
    try writer.writeAll(builtin);
}

fn getBlockName(block: *const ssa.Block) []const u8 {
    switch (block.*) {
        .Decision => return block.*.Decision.name,
        .Sequential => return block.*.Sequential.name,
    }
}

///.data
/// none: .string "None"
/// true: .string "True"
/// false: .string "False"
/// integer: .string "%d"
fn writeData(writer: std.io.AnyWriter, const_strings: std.StringHashMap([]const u8)) !void {
    try writer.writeAll(".data\n");
    try writer.writeAll(Indent);
    try writer.writeAll("none: .string \"None\"\n");
    try writer.writeAll(Indent);
    try writer.writeAll("true: .string \"True\"\n");
    try writer.writeAll(Indent);
    try writer.writeAll("false: .string \"False\"\n");
    try writer.writeAll(Indent);
    try writer.writeAll("integer: .string \"%d\"\n");
    try writer.writeAll(Indent);
    try writer.writeAll("newline: .string \"\\n\"\n");
    try writer.writeAll(Indent);
    try writer.writeAll("panic_str: .string \"error\\n\\0\"\n");
    var it = const_strings.iterator();
    while (it.next()) |_| {}
    try writer.writeAll(".section .note.GNU-stack,\"\",@progbits\n");
}
