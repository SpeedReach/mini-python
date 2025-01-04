pub const std = @import("std");
pub const ds = @import("./ds/ds.zig");
const lex = @import("lexer/lexer.zig");
const ast = @import("ast/ast.zig");
const cfgir = @import("cfgir/cfgir.zig");
const parse = @import("parser/parser.zig");
const dom = @import("ssa/dom_tree.zig");
const ssa = @import("ssa/ssa.zig");
const codegen = @import("codegen/codegen.zig");

pub fn compile(out: std.io.AnyWriter, code: [:0]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = parse.Parser.init(allocator, code);
    const ast_file = parser.parse() catch |err| {
        std.debug.print("Error {}: {s}\n", .{ err, parser.diagnostics });
        return;
    };

    const cfg = try cfgir.astToCfgIR(allocator, ast_file);
    const ssa_ir = try ssa.construct.constructSSA(allocator, cfg);
    try codegen.generate(out, ssa_ir);
    ssa.print(ssa_ir);
}

pub fn main() !void {
    // const code =
    //     \\print(1+2)
    //     \\
    // ;
    // try compile(code);
    var args = std.process.args(); //why does this only compile with "var"??
    _ = args.skip(); //to skip the zig call

    const path = args.next().?;
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const file_size = (try file.stat()).size;
    const allocator = std.heap.page_allocator;
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);

    const imm_buffer: [:0]const u8 = @ptrCast(buffer);

    const out_file = try std.fs.cwd().createFile(
        "asm.S",
        .{ .read = true },
    );
    try compile(out_file.writer().any(), imm_buffer);
}
