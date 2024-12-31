pub const std = @import("std");
pub const ds = @import("./ds/ds.zig");
const lex = @import("lexer/lexer.zig");
const ast = @import("ast/ast.zig");
const cfgir = @import("cfgir/cfgir.zig");
const parse = @import("parser/parser.zig");
const dom = @import("ssa/dominance_tree.zig");

pub fn compile(code: [:0]const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var parser = parse.Parser.init(allocator, code);
    const ast_file = try parser.parse();

    const main_cfg = try cfgir.astStatementsToCFG(allocator, ast_file.statements.items, "top%level%statements");
    try cfgir.generateMermaidDiagram(main_cfg, std.io.getStdErr().writer().any());
    for (ast_file.defs.items) |def| {
        const cfg = try cfgir.astStatementsToCFG(allocator, def.body.statements.items, def.name);
        try cfgir.generateMermaidDiagram(cfg, std.io.getStdErr().writer().any());
    }
    //const dom_tree = try dom.computeDominaceTree(allocator, &main_cfg);
    //dom.print_dom_tree(dom_tree);
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

    try compile(imm_buffer);
}
