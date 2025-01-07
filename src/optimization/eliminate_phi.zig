const std = @import("std");
const ssa = @import("../ssa/ssa.zig");

// Replace Phi with move instruction(which is assign bassically)
// This is mandatory and should be the last optimization pass
pub fn apply(program: *ssa.Program) !void {
    var it = program.functions.iterator();
    while (it.next()) |entry| {
        try applyContext(entry.value_ptr);
    }
    try applyContext(&program.main);
}

fn applyContext(context: *ssa.FunctionContext) !void {
    var it = context.*.blocks.iterator();
    while (it.next()) |entry| {
        try applyMoveOnBlock(entry.value_ptr.*, &context.blocks);
    }

    it = context.*.blocks.iterator();
    while (it.next()) |entry| {
        try applyRemovePhi(entry.value_ptr.*);
    }
}

fn applyMoveOnBlock(block: *ssa.Block, blocks: *std.AutoHashMap(u32, *ssa.Block)) !void {
    const phiInstructions = getPhiInstructions(block);
    const firstNotPhiIndex = getFirstNotPhiIndex(phiInstructions);
    for (0..firstNotPhiIndex) |i| {
        const inst = phiInstructions.items[i];
        for (inst.Assignment.rhs.Phi.values.items) |value| {
            const from_block = blocks.get(value.block).?;
            switch (from_block.*) {
                .Decision => {
                    // Conditional blocks doesn't have assignments
                    // So no need to move
                },
                .Sequential => {
                    try from_block.*.Sequential.instructions.append(ssa.Instruction{ .Assignment = ssa.Assignment{
                        .variable = inst.Assignment.variable,
                        .rhs = .{ .Value = value.value },
                    } });
                },
            }
        }
    }
}

fn getPhiInstructions(block: *const ssa.Block) *const std.ArrayList(ssa.Instruction) {
    return if (block.* == .Decision) &block.*.Decision.instructions else &block.*.Sequential.instructions;
}

fn getFirstNotPhiIndex(instructions: *const std.ArrayList(ssa.Instruction)) usize {
    for (0..instructions.items.len) |i| {
        const instruction = instructions.items[i];
        if (instruction == .Assignment and instruction.Assignment.rhs == .Phi) {
            continue;
        }
        return i;
    }
    return 0;
}

fn applyRemovePhi(block: *ssa.Block) !void {
    var inst = if (block.* == .Decision) &block.*.Decision.instructions else &block.*.Sequential.instructions;
    for (0..inst.items.len) |i| {
        const ins = inst.items[i];
        if (ins == .Assignment and ins.Assignment.rhs == .Phi) {
            inst.items[i] = .NoOp;
        }
    }
}
