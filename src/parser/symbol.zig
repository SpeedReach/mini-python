const lexer = @import("../lexer/lexer.zig");

pub const Symbol = union(enum) {
    terminals: Terminal,
    none_terminals: NoneTerminal,
};

pub const NoneTerminal = enum {
    file,
    def,
    suite,
    simple_stmt,
    stmt,
    expr,
    bin_op,
    constant,
};

pub const Terminal = enum {
    new_line,
    begin,
    end,
    eof,
    def,
    identifier,
    add,
    sub,
    mul,
    // "//"
    div,
    // %
    percent,
    /// ==
    equal_equal,
    ne,
    /// <
    lt,
    /// <=
    le,
    /// >
    gt,
    /// >=
    ge,
    /// =
    equal,
    @"and",
    @"or",
    space,
    int,
    string,
    true,
    false,
    none,
    /// (
    l_paren,
    /// )
    r_paren,
    /// {
    l_brace,
    /// }
    r_brace,
    comma,
    /// [
    l_bracket,
    /// ]
    r_bracket,
    @"return",
    @"else",
    @"for",
    @"if",
    in,
    not,
    print,
    invalid,

    pub fn from_token(token: lexer.Token) Terminal {
        switch (token) {
            .new_line => return .new_line,
            .begin => return .begin,
            .end => return .end,
            .raw => |raw| {
                switch (raw.tag) {
                    .def => return .def,
                    .identifier => return .identifier,
                    .add => return .add,
                    .sub => return .sub,
                    .mul => return .mul,
                    .div => return .div,
                    .percent => return .percent,
                    .equal_equal => return .equal_equal,
                    .ne => return .ne,
                    .lt => return .lt,
                    .le => return .le,
                    .gt => return .gt,
                    .ge => return .ge,
                    .equal => return .equal,
                    .@"and" => return .@"and",
                    .@"or" => return .@"or",
                    .space => return .space,
                    .int => return .int,
                    .string => return .string,
                    .true => return .true,
                    .false => return .false,
                    .none => return .none,
                    .l_paren => return .l_paren,
                    .r_paren => return .r_paren,
                    .l_brace => return .l_brace,
                    .r_brace => return .r_brace,
                    .comma => return .comma,
                    .l_bracket => return .l_bracket,
                    .r_bracket => return .r_bracket,
                    .@"return" => return .@"return",
                    .@"else" => return .@"else",
                    .@"for" => return .@"for",
                    .@"if" => return .@"if",
                    .in => return .in,
                    .not => return .not,
                    .print => return .print,
                    else => return .invalid,
                }
            },
        }
    }
};

const testing = @import("std").testing;

test "test from" {
    const token = lexer.Token.new_line;
    const terminal = Terminal.from_token(token);
    try testing.expect(terminal == Terminal.new_line);
}
