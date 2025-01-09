const std = @import("std");
const lex = @import("../lexer/lexer.zig");
const ast = @import("../ast/ast.zig");

const Symbol = @import("./symbol.zig").Symbol;
const Terminal = @import("./symbol.zig").Terminals;

pub const Error = error{ParsingFailed} || std.mem.Allocator.Error;
pub const Message = @import("./diagnostics.zig").Message;
pub const DiagnosticErr = @import("./diagnostics.zig").Error;

const ExprParser = @import("./expr_parser.zig").ExprParser;
const RawToken = @import("../lexer/token.zig").RawToken;

pub const Parser = struct {
    code: [:0]const u8,
    lexer: lex.Lexer,
    parse_stack: std.ArrayList(Symbol),
    allocator: std.mem.Allocator,
    diagnostics: []const u8 = "",

    pub fn init(allocator: std.mem.Allocator, buffer: [:0]const u8) Parser {
        const lexer = lex.Lexer.init(allocator, buffer);
        return .{ .allocator = allocator, .code = buffer, .lexer = lexer, .parse_stack = std.ArrayList(Symbol).init(allocator) };
    }

    fn parseDef(self: *Parser) anyerror!ast.Def {
        try self.expectRaw(RawToken.Tag.def);
        const identifier = try self.lexer.next();
        if (identifier != .raw or identifier.raw.tag != RawToken.Tag.identifier) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect identifier, got {} at position {}", .{
                identifier,
                self.lexer.pos(),
            });
            return Error.ParsingFailed;
        }
        const argumentNames = try self.parseArgumentNames();
        const colon = try self.lexer.next();
        if (colon != .raw or colon.raw.tag != RawToken.Tag.colon) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect :, got {} at position {}", .{ colon, self.lexer.pos() });
            return Error.ParsingFailed;
        }

        var suite = try self.parseSuite();
        const return_expr = try self.allocator.create(ast.Expr);
        return_expr.* = ast.Expr{ .@"const" = ast.Const.none };
        try suite.statements.append(ast.Statement{ .simple_statement = ast.SimpleStatement{ .@"return" = return_expr } });
        return ast.Def{ .name = self.code[identifier.raw.loc.start..identifier.raw.loc.end], .body = suite, .params = argumentNames };
    }

    /// parse (a1,a2,a3)
    /// and return a[] as ast.Expr
    fn parseArgumentNames(self: *Parser) anyerror!std.ArrayList([]const u8) {
        const l_paren = try self.lexer.next();
        if (l_paren != .raw and l_paren.raw.tag != RawToken.Tag.l_paren) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect (, got {} at position {}", .{ l_paren, self.lexer.pos() });
            return Error.ParsingFailed;
        }
        var argumentNames = std.ArrayList([]const u8).init(self.allocator);
        while (true) {
            const id_token = try self.lexer.next();
            if (id_token != .raw) {
                self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect identifier, got {} at position {}", .{
                    id_token,
                    self.lexer.pos(),
                });
                return Error.ParsingFailed;
            }
            if (id_token.raw.tag == RawToken.Tag.r_paren) {
                return argumentNames;
            }
            try argumentNames.append(self.code[id_token.raw.loc.start..id_token.raw.loc.end]);
            const end_token = try self.lexer.next();
            switch (end_token) {
                .raw => |raw| {
                    switch (raw.tag) {
                        .comma => {
                            continue;
                        },
                        .r_paren => {
                            return argumentNames;
                        },
                        else => {
                            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect , or ), got {} at position {}", .{ end_token, self.lexer.pos() });
                            return Error.ParsingFailed;
                        },
                    }
                },
                else => {
                    self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect , or ), got {} at position {}", .{ end_token, self.lexer.pos() });
                    return Error.ParsingFailed;
                },
            }
        }
    }
    fn parseStatement(self: *Parser) anyerror!ast.Statement {
        const token = try self.lexer.peek();
        switch (token) {
            .raw => |raw| {
                switch (raw.tag) {
                    .@"if" => {
                        return try self.parseIf();
                    },
                    .@"for" => {
                        const for_in = try self.parseForIn();
                        return ast.Statement{ .for_in_statement = for_in };
                    },
                    .eof => {
                        return Error.ParsingFailed;
                    },
                    .comment => {
                        _ = try self.lexer.next();
                        return try self.parseStatement();
                    },
                    else => {
                        const simple_statement = try self.parseSimpleStatement();
                        return ast.Statement{ .simple_statement = simple_statement };
                    },
                }
            },
            else => {
                return Error.ParsingFailed;
            },
        }
    }
    fn parseSuite(self: *Parser) anyerror!ast.Suite {
        if (try self.lexer.peek() != .new_line) {
            var statements = std.ArrayList(ast.Statement).init(self.allocator);
            const statement = try self.parseSimpleStatement();
            try statements.append(ast.Statement{ .simple_statement = statement });
            try self.expect(lex.TokenTag.new_line);
            return ast.Suite{
                .statements = statements,
            };
        }
        try self.expect(lex.TokenTag.new_line);
        try self.expect(lex.TokenTag.begin);
        var statements = std.ArrayList(ast.Statement).init(self.allocator);
        while (true) {
            const token = try self.lexer.peek();
            switch (token) {
                .new_line => {
                    _ = try self.lexer.next();
                    continue;
                },
                .begin => {
                    return Error.ParsingFailed;
                },
                .end => {
                    _ = try self.lexer.next();

                    return ast.Suite{
                        .statements = statements,
                    };
                },
                .raw => |raw| {
                    if (raw.tag == .eof) {
                        return ast.Suite{
                            .statements = statements,
                        };
                    }
                    try statements.append(try self.parseStatement());
                },
            }
        }
        return Error.ParsingFailed;
    }

    fn parseForIn(self: *Parser) !ast.ForInStatement {
        try self.expectRaw(RawToken.Tag.@"for");
        const ident = try self.lexer.next();
        if (ident != .raw and ident.raw.tag != RawToken.Tag.identifier) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect identifier, got {} at position {}", .{ ident, self.lexer.pos() });
            return Error.ParsingFailed;
        }
        try self.expectRaw(RawToken.Tag.in);
        const expr = try self.parseExpr();
        try self.expectRaw(RawToken.Tag.colon);
        const suite = try self.parseSuite();
        return ast.ForInStatement{
            .var_name = self.code[ident.raw.loc.start..ident.raw.loc.end],
            .iterable = expr,
            .body = suite,
        };
    }

    fn expectRaw(self: *Parser, tag: RawToken.Tag) !void {
        const token = try self.lexer.next();
        if (token != .raw or token.raw.tag != tag) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect {}, got {} at position {}", .{ tag, token, self.lexer.pos() });
            return Error.ParsingFailed;
        }
    }
    fn expect(self: *Parser, tag: lex.TokenTag) !void {
        const token = try self.lexer.next();
        if (token != tag) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect {}, got {} at position {}", .{ tag, token, self.lexer.pos() });
            return Error.ParsingFailed;
        }
    }

    fn parseSimpleStatement(self: *Parser) !ast.SimpleStatement {
        const token = try self.lexer.peek();
        if (token != .raw) {
            return Error.ParsingFailed;
        }
        switch (token.raw.tag) {
            RawToken.Tag.@"return" => {
                return try self.parseReturn();
            },
            RawToken.Tag.print => {
                return try self.parsePrint();
            },
            else => {
                const left = try self.parseExpr();
                switch (left.*) {
                    ast.ExprTag.ident => {
                        try self.expectRaw(RawToken.Tag.equal);

                        const right = try self.parseExpr();
                        return ast.SimpleStatement{ .assign = ast.SimpleAssignment{ .lhs = left.ident, .rhs = right } };
                    },
                    ast.ExprTag.list_access => |list_access| {
                        try self.expectRaw(RawToken.Tag.equal);
                        const right = try self.parseExpr();
                        return ast.SimpleStatement{ .assign_list = ast.ListWrite{
                            .lhs = list_access.list,
                            .idx = list_access.idx,
                            .rhs = right,
                        } };
                    },
                    else => {
                        //try self.expect(lex.TokenTag.new_line);
                        return ast.SimpleStatement{
                            .expr = left,
                        };
                    },
                }
            },
        }
    }

    fn parsePrint(self: *Parser) !ast.SimpleStatement {
        try self.expectRaw(RawToken.Tag.print);
        const value = try self.parseExpr();
        return ast.SimpleStatement{ .print = ast.Print{ .value = value } };
    }

    fn parseReturn(self: *Parser) !ast.SimpleStatement {
        try self.expectRaw(RawToken.Tag.@"return");
        const next = try self.lexer.peek();
        if (next == .new_line) {
            const expr = try self.allocator.create(ast.Expr);
            expr.* = ast.Expr{ .@"const" = ast.Const.none };
            return ast.SimpleStatement{ .@"return" = expr };
        }
        const expr = try self.parseExpr();
        return ast.SimpleStatement{ .@"return" = expr };
    }

    fn parseFunctionArgs(self: *Parser) !std.ArrayList(*ast.Expr) {
        const l_paren = try self.lexer.next();
        if (l_paren != .raw or l_paren.raw.tag != RawToken.Tag.l_paren) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect (, got {} at position {}", .{ l_paren, self.lexer.pos() });
            return null;
        }
        var function_args = std.ArrayList(*ast.Expr).init(self.allocator);
        while (true) {
            const arg = try self.parseExpr();
            try function_args.append(arg);
            const maybe_comma = try self.lexer.peek();
            if (maybe_comma == .raw and maybe_comma.raw.tag == RawToken.Tag.comma) {
                _ = try self.lexer.next();
                continue;
            }
            if (maybe_comma == .raw and maybe_comma.raw.tag == RawToken.Tag.r_paren) {
                _ = try self.lexer.next();
                break;
            }
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect , or ), got {} at position {}", .{ maybe_comma, self.lexer.pos() });
            return Error.ParsingFailed;
        }
        return function_args;
    }

    const ParseElement = union(enum) {
        Const: ast.Const,
        Ident: []const u8,
        l_paren,
    };

    fn parseExpr(self: *Parser) !*ast.Expr {
        var parser = ExprParser.init(self.allocator, &self.lexer);
        const expr = try self.allocator.create(ast.Expr);
        expr.* = try parser.parse(0);
        return expr;
    }

    fn parseConst(self: *Parser, tok: RawToken) !ast.Const {
        switch (tok.tag) {
            RawToken.Tag.int => {
                const int = try std.fmt.parseInt(i64, self.code[tok.loc.start..tok.loc.end], 10);
                return ast.Const{
                    .int = int,
                };
            },
            RawToken.Tag.string => {
                return ast.Const{
                    .string = self.code[tok.loc.start..tok.loc.end],
                };
            },
            RawToken.Tag.true => {
                return ast.Const{ .boolean = true };
            },
            RawToken.Tag.false => {
                return ast.Const{ .boolean = false };
            },
            RawToken.Tag.none => {
                return ast.Const{ .none = true };
            },
            else => {
                self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect const, got {} at position {}", .{ tok, self.lexer.pos() });
                return Error.ParsingFailed;
            },
        }
    }

    fn parseIf(self: *Parser) anyerror!ast.Statement {
        try self.expectRaw(RawToken.Tag.@"if");
        const condition = try self.parseExpr();
        try self.expectRaw(RawToken.Tag.colon);
        const suite = try self.parseSuite();
        const maybe_else = try self.lexer.peek();
        if (maybe_else != .raw or maybe_else.raw.tag != RawToken.Tag.@"else") {
            return ast.Statement{ .if_statement = ast.IfStatement{
                .condition = condition,
                .body = suite,
            } };
        }
        _ = try self.lexer.next();
        try self.expectRaw(RawToken.Tag.colon);
        const else_suite = try self.parseSuite();
        return ast.Statement{ .if_else_statement = ast.IfElseStatement{
            .condition = condition,
            .if_body = suite,
            .else_body = else_suite,
        } };
    }

    pub fn parse(self: *Parser) anyerror!ast.AstFile {
        var defs = std.ArrayList(ast.Def).init(self.allocator);
        var statements = std.ArrayList(ast.Statement).init(self.allocator);

        while (true) {
            const token = try self.lexer.peek();
            switch (token) {
                .new_line => {
                    _ = try self.lexer.next();
                    continue;
                },
                .raw => |raw| {
                    switch (raw.tag) {
                        .def => {
                            const def = try self.parseDef();
                            try defs.append(def);
                        },
                        .eof => {
                            break;
                        },
                        else => {
                            const statement = try self.parseStatement();
                            try statements.append(statement);
                        },
                    }
                },
                else => {
                    self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect def, got {} at position {}", .{ token, self.lexer.pos() });
                    return Error.ParsingFailed;
                },
            }
        }

        return ast.AstFile{
            .defs = defs,
            .statements = statements,
        };
    }
};

const testing = std.testing;

test "parse def 1" {
    const ast_print = @import("../ast/print.zig");
    var arenaAllocator = std.heap.ArenaAllocator.init(testing.allocator);
    defer arenaAllocator.deinit();
    const allocator = arenaAllocator.allocator();
    const code =
        \\def add(a):
        \\  return 1
    ;
    var parser = Parser.init(allocator, code);
    const ast_file = parser.parse() catch |err| {
        std.debug.print("{} at {}\n", .{ err, parser.lexer.pos() });
        std.debug.print("reason: {s}\n", .{parser.diagnostics});
        return err;
    };

    try ast_print.print_ast(std.io.getStdErr().writer().any(), ast_file);
}

test "parse def 2" {
    const ast_print = @import("../ast/print.zig");
    var arenaAllocator = std.heap.ArenaAllocator.init(testing.allocator);
    defer arenaAllocator.deinit();
    const allocator = arenaAllocator.allocator();
    const code =
        \\
        \\def add(a,b1):
        \\  c = a + b2 * b3
        \\  if c < 10:
        \\    if c < 5:
        \\      return 2
        \\    return 1
        \\  return 0
        \\def sub(a,b):
        \\  return a - b
        \\def test(a,v , dd):
        \\  return
        \\print(test(1,2,3))
        \\print("hello")
    ;
    var parser = Parser.init(allocator, code);
    const ast_file = parser.parse() catch |err| {
        std.debug.print("{} at {}\n", .{ err, parser.lexer.pos() });
        std.debug.print("reason: {s}\n", .{parser.diagnostics});
        return err;
    };

    try ast_print.print_ast(std.io.getStdErr().writer().any(), ast_file);
}

test "parse def 3" {
    const ast_print = @import("../ast/print.zig");
    var arenaAllocator = std.heap.ArenaAllocator.init(testing.allocator);
    defer arenaAllocator.deinit();
    const allocator = arenaAllocator.allocator();
    const code =
        \\print("www")
        \\print("www")
    ;
    var parser = Parser.init(allocator, code);
    const ast_file = parser.parse() catch |err| {
        std.debug.print("{} at {}\n", .{ err, parser.lexer.pos() });
        std.debug.print("reason: {s}\n", .{parser.diagnostics});
        return err;
    };

    try ast_print.print_ast(std.io.getStdErr().writer().any(), ast_file);
}
