pub const ds = @import("./ds/ds.zig");
pub const lexer = @import("lexer/lexer.zig");
pub const ast = @import("ast/ast.zig");
pub const codegen = @import("codegen/codegen.zig");
pub const hir = @import("hir/hir.zig");

test {
    _ = @import("lexer/lexer.zig");
    _ = @import("codegen/codegen.zig");
    _ = @import("codegen/x86_64.zig");
    _ = @import("hir/hir.zig");
}
