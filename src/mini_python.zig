pub const ds = @import("./ds/ds.zig");
pub const lexer = @import("lexer/lexer.zig");
pub const ast = @import("ast/ast.zig");
pub const codegen = @import("codegen/codegen.zig");
pub const cfgir = @import("cfgir/cfgir.zig");
pub const utils = @import("utils/utils.zig");
pub const parser = @import("parser/parser.zig");

test {
    _ = @import("lexer/lexer.zig");
    _ = @import("codegen/codegen.zig");
    _ = @import("codegen/x86_64.zig");
    _ = @import("cfgir/cfgir.zig");
    _ = @import("parser/parser.zig");
}
