pub const Block = struct {
    brancing: Branching,
};

pub const Branching = struct {
    condition: Expression,
    then_block: Block,
    else_block: Block,
};

pub const StatementTag = enum { @"return", assign, assign_list, print, expr };

pub const Statement = struct {
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
