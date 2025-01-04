const ssa = @import("../ssa/ssa.zig");
const std = @import("std");
const x64 = @import("x86_64.zig");

const Indent = "    ";
const exitBlockId = std.math.maxInt(u32);
const VarName = []const u8;
const Allocator = std.mem.Allocator;

pub fn generate(writer: std.io.AnyWriter, program: ssa.Program) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    try writeData(writer);
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

fn writeBlock(allocator: std.mem.Allocator, writer: std.io.AnyWriter, block: ssa.Block, blocks: *const std.AutoHashMap(u32, *ssa.Block), rbp_offset: *const std.StringHashMap(i64)) !void {
    switch (block) {
        .Decision => {
            try writer.print("{s}:\n", .{block.Decision.name});
            try writeInstructions(allocator, writer, block.Decision.instructions, rbp_offset);
            //Check condition is true then jump
        },
        .Sequential => {
            try writer.print("{s}:\n", .{block.Sequential.name});
            try writeInstructions(allocator, writer, block.Sequential.instructions, rbp_offset);
            if (block.Sequential.id != exitBlockId) {
                const nextBlockName = try getBlockName(blocks.get(exitBlockId).?);
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
                try w.print("{s}call    print\n", .{Indent});
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
            .WriteArr => |_| {
                //TODO
            },
        }
    }
}

/// Allocates memory on the heap for the constant
/// The pointer to the memory is stored in %rax
fn writeConst(w: std.io.AnyWriter, cnst: ssa.Const) !void {
    switch (cnst) {
        .none => {
            try w.print("{s}malloc  $16", .{Indent});
            try w.print("{s}movq    $0, (%rax)\n", .{Indent});
            try w.print("{s}movq    $0, 8(%rax)\n", .{Indent});
        },
        .boolean => {
            try w.print("{s}malloc  $16", .{Indent});
            try w.print("{s}movq    $1, (%rax)\n", .{Indent});
            try w.print("{s}movq    ${d}, 8(%rax)\n", .{ Indent, @as(i64, if (cnst.boolean) 1 else 0) });
        },
        .int => {
            try w.print("{s}malloc  $16\n", .{Indent});
            try w.print("{s}movq    $2, (%rax)\n", .{Indent});
            try w.print("{s}movq    ${d}, 8(%rax)\n", .{ Indent, cnst.int });
        },
        .string => {
            //TODO: Implement string constant
            //Maybe use .data section
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
            for (function_call.args.items) |arg| {
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
            try w.print("{s}call    {s}\n", .{ Indent, function_call.name });
            try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
        },
        .Load => |load| {
            try w.print("{s}movq    ({s}), %rax\n", .{ Indent, load });
            try w.print("{s}movq    %rax, {d}(%rbp)\n", .{ Indent, assign_offset });
        },
        .ListValue => |list| {
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
                        try w.print("{s}movq    %rax,   {d}(%rsp)\n", .{ Indent, i * 8 });
                    },
                    .Var => {
                        const varname = try getVarName(allocator, item.Var);
                        defer allocator.free(varname);
                        const offset = rbp_offsets.get(varname).?;
                        try w.print("{s}movq    {d}(%rbp),  %rax \n", .{ Indent, offset });
                        try w.print("{s}movq    %rax,   {d}(%rsp)\n", .{ Indent, i * 8 });
                    },
                }
            }
            try w.print("{s}popq    %rax\n", .{Indent});
        },
        else => {},
    }
}

///Result should be in %rax, as a pointer to the heap allocated memory
fn writeBinOp(allocator: Allocator, w: std.io.AnyWriter, bin_op: ssa.BinOpExpr, rbp_offsets: *const std.StringHashMap(i64)) !void {
    switch (bin_op.op) {
        .add => {
            if (bin_op.lhs == .Var and bin_op.rhs == .Var) {
                const lhs_varname = try getVarName(allocator, bin_op.lhs.Var);
                defer allocator.free(lhs_varname);
                const lhs_offset = rbp_offsets.get(lhs_varname).?;
                const rhs_varname = try getVarName(allocator, bin_op.rhs.Var);
                defer allocator.free(rhs_varname);
                const rhs_offset = rbp_offsets.get(rhs_varname).?;
                try w.print("{s}movq    {d}(%rbp),  %rdi\n", .{ Indent, lhs_offset });
                try w.print("{s}movq    {d}(%rbp),  %rsi\n", .{ Indent, rhs_offset });
                try w.print("{s}call    _builtin_add    \n", .{Indent});
                return;
            }
            //We assume constant folding is applied, so atmost one side is a constant
            const cnst = if (bin_op.lhs == .Var) bin_op.rhs.Const else bin_op.lhs.Const;
            const variable = if (bin_op.lhs == .Var) bin_op.lhs.Var else bin_op.rhs.Var;
            const varname = try getVarName(allocator, variable);
            defer allocator.free(varname);
            const offset = rbp_offsets.get(varname).?;
            if (cnst == .int) {
                //check if variable is int
                try w.print("{s}movq    {d}(%rbp),  %rax\n", .{ Indent, offset });
                try w.print("{s}movq    (%rax),     %rcx\n", .{Indent});
                try w.print("{s}cmpq    $2,         %rcx\n", .{Indent});
                try w.print("{s}jne     runtime_panic   \n", .{Indent});
                try w.print("{s}movq    8(%rax),    %rax\n", .{Indent});
                try w.print("{s}addq    ${d},       %rax\n", .{ Indent, cnst.int });
                try w.print("{s}pushq   %rax            \n", .{Indent});
                try w.print("{s}malloc  $16             \n", .{Indent});
                try w.print("{s}movq    $2,     (%rax)  \n", .{Indent});
                try w.print("{s}popq    %r9             \n", .{Indent});
                try w.print("{s}movq    %r9,     8(%rax)\n", .{Indent});
                return;
            }
            if (cnst == .string) {
                try w.print("{s}movq    {d}(%rbp),  %rax\n", .{ Indent, offset });
                try w.print("{s}movq    (%rax),     %rcx\n", .{Indent});
                try w.print("{s}cmpq    $3,         %rcx\n", .{Indent});
                try w.print("{s}jne     runtime_panic   \n", .{Indent});
                //TODO: Implement string addition
                //Need to figure out how string constant is stored
            }
        },
        else => {},
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

fn getBlockName(block: *const ssa.Block) ![]const u8 {
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
fn writeData(writer: std.io.AnyWriter) !void {
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
    try writer.writeAll("panic_str: .string \"error\n\"\n");
}
