pub const std = @import("std");
pub const ds = @import("./ds/ds.zig");
const lex = @import("lexer/lexer.zig");
const ast = @import("ast/ast.zig");
const cfgir = @import("cfgir/cfgir.zig");
const parse = @import("parser/parser.zig");
const dom = @import("ssa/dom_tree.zig");
const ssa = @import("ssa/ssa.zig");
const codegen = @import("codegen/codegen.zig");
const opt = @import("optimization/optimization.zig");

pub fn compile(out: std.io.AnyWriter, code: [:0]const u8, type_only: bool) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = parse.Parser.init(allocator, code);
    const ast_file = try parser.parse();
    if (type_only) {
        return;
    }

    const cfg = try cfgir.astToCfgIR(allocator, ast_file);

    var ssa_ir = try ssa.construct.constructSSA(allocator, cfg);

    _ = try opt.const_fold.apply(allocator, &ssa_ir);
    ssa.print(ssa_ir);
    std.debug.print("\n\n------------------after optimized------------------\n\n", .{});
    try opt.elimnate_phi.apply(&ssa_ir);
    ssa.print(ssa_ir);
    try codegen.generate(out, ssa_ir);
}

pub fn main() !void {
    // const code =
    //     \\print(1+2)
    //     \\
    // ;
    // try compile(code);
    var args = std.process.args(); //why does this only compile with "var"??
    _ = args.skip(); //to skip the zig call

    const first = args.next().?;
    var path: []const u8 = undefined;
    var type_only = false;
    if (std.mem.eq("--type-only", first)) {
        path = args.next().?;
        type_only = true;
    } else {
        path = first;
    }

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    const file_size = (try file.stat()).size;
    const allocator = std.heap.page_allocator;
    const buffer = try allocator.alloc(u8, file_size);
    _ = try file.readAll(buffer);

    const imm_buffer: [:0]const u8 = @ptrCast(buffer);

    const out_file = try std.fs.cwd().createFile(
        try std.fmt.allocPrint(allocator, "{s}.s", .{path[0 .. path.len - 3]}),
        .{ .read = true },
    );
    try compile(out_file.writer().any(), imm_buffer, type_only);
}
