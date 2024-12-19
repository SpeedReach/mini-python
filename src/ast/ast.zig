pub const Ident = []const u8;

pub const AstFile = struct {
    defs: []const Def,
    // atleast 1 statement is required
    statements: []const Statement,
};

/// def ⟨ident⟩ ( ⟨ident⟩∗, ) : ⟨suite⟩
pub const Def = struct {
    name: Ident,
    params: []const Ident,
    body: Suite,
};

pub const SuiteTag = enum { simple_statement, statement };

pub const Suite = union(SuiteTag) {
    /// ⟨simple stmt⟩ NEWLINE
    simple_statement: SimpleStatement,
    /// NEWLINE BEGIN⟨stmt⟩+ END
    statement: []const Statement,
};

pub const SimpleStatementTag = enum { @"return", assign, assign_list, print, expr };

pub const SimpleStatement = union(SimpleStatementTag) {
    /// return ⟨expr⟩
    @"return": *const Expr,
    /// ⟨ident⟩ = ⟨expr⟩
    assign: SimpleAssignment,
    /// ⟨expr ⟩ [ ⟨expr ⟩ ] =⟨expr ⟩
    assign_list: ListAssignent,
    /// print ( ⟨expr ⟩ )
    print: Print,
    /// ⟨expr ⟩
    expr: *const Expr,
};

pub const SimpleAssignment = struct {
    lhs: Ident,
    rhs: *const Expr,
};

pub const ListAssignent = struct {
    lhs: *const Expr,
    idx: *const Expr,
    rhs: *const Expr,
};

pub const Print = struct {
    value: *const Expr,
};

pub const StatementTag = enum {
    simple_statement,
    if_statement,
    if_else_statement,
    for_in_statement,
};

pub const Statement = union(StatementTag) {
    simple_statement: SimpleStatement,
    if_statement: IfStatement,
    if_else_statement: IfElseStatement,
    for_in_statement: ForInStatement,
};

pub const IfStatement = struct {
    condition: *const Expr,
    body: Suite,
};

pub const IfElseStatement = struct {
    condition: Expr,
    if_body: Suite,
    @"else": *const Expr,
};

pub const ForInStatement = struct {
    var_name: Ident,
    iterable: *const Expr,
    body: Suite,
};

pub const ExprTag = enum {
    @"const",
    ident,
    list_access,
    unary_expr,
    not_expr,
    bin_op,
    function_call,
    list_declare,
    paren_expr,
};

pub const Expr = union(ExprTag) {
    @"const": Const,
    ident: Ident,
    list_access: ListAccess,
    unary_expr: *const Expr,
    not_expr: *const Expr,
    bin_op: BinOpExpr,
    function_call: FunctionCall,
    list_declare: ListDeclare,
    paren_expr: ParenExpr,
};

pub const ConstTag = enum { int, string, true, false, none };

pub const Const = union(ConstTag) { int: i64, string: []const u8, true, false, none };

pub const ListAccess = struct {
    list: *const Expr,
    idx: *const Expr,
};

pub const BinOpExpr = struct {
    lhs: *const Expr,
    op: BinOp,
    rhs: *const Expr,
};

pub const FunctionCall = struct {
    name: Ident,
    args: []const *const Expr,
};

pub const ListDeclare = struct {
    values: []const *const Expr,
};

pub const ParenExpr = struct {
    expr: *const Expr,
};

pub const BinOp = enum {
    add,
    sub,
    mul,
    div,
    // %
    mod,
    eq,
    ne,
    // <
    lt,
    // <=
    le,
    // >
    gt,
    // >=
    ge,
    @"and",
    @"or",
};

const std = @import("std");
const testing = std.testing;

test "can compile" {
    //const gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const file = AstFile{
        .defs = &[_]Def{
            Def{
                .name = "add",
                .params = &[_]Ident{ "a", "b" },
                .body = Suite{
                    .simple_statement = SimpleStatement{
                        .assign = SimpleAssignment{
                            .lhs = "result",
                            .rhs = &Expr{
                                .bin_op = BinOpExpr{
                                    .lhs = &Expr{ .ident = "a" },
                                    .op = BinOp.add,
                                    .rhs = &Expr{ .ident = "b" },
                                },
                            },
                        },
                    },
                },
            },
        },
        .statements = &[_]Statement{
            Statement{
                .simple_statement = SimpleStatement{
                    .expr = &Expr{
                        .function_call = FunctionCall{
                            .name = "add",
                            .args = &[_]*const Expr{
                                &Expr{ .@"const" = Const{ .int = 3 } },
                                &Expr{ .@"const" = Const{ .int = 7 } },
                            },
                        },
                    },
                },
            },
        },
    };
    try testing.expect(file.defs.len == 1);
}
