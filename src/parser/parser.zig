const std = @import("std");
const lex = @import("../lexer/lexer.zig");
const ast = @import("../ast/ast.zig");

const Symbol = @import("./symbol.zig").Symbol;
const Terminal = @import("./symbol.zig").Terminals;

pub const Error = error{ParsingFailed} || std.mem.Allocator.Error;
pub const Message = @import("./diagnostics.zig").Message;
pub const DiagnosticErr = @import("./diagnostics.zig").Error;

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
        const def = try self.lexer.next();
        if (def != .raw or def.raw.tag != RawToken.Tag.def) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect def, got {} at position {}", .{ def, self.lexer.pos() });
            return Error.ParsingFailed;
        }

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
        const new_line = try self.lexer.next();
        if (new_line != lex.TokenTag.new_line) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect new line, got {} at position {}", .{ new_line, self.lexer.pos() });
            return Error.ParsingFailed;
        }
        const begin = try self.lexer.next();
        if (begin != lex.TokenTag.begin) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect begin, got {} at position {}", .{ begin, self.lexer.pos() });
            return Error.ParsingFailed;
        }
        const suite = try self.parseSuite();
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

    fn parseSuite(self: *Parser) anyerror!ast.Suite {
        var statements = std.ArrayList(ast.Statement).init(self.allocator);
        while (true) {
            const token = try self.lexer.peek();
            switch (token) {
                .new_line => {
                    _ = try self.lexer.next();
                    continue;
                },
                .begin | .end => {
                    self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect statement, got {} at position {}", .{ token, self.lexer.pos() });
                    return Error.ParsingFailed;
                },
                .raw => |raw| {
                    switch (raw.tag) {
                        .@"if" => {
                            const if_statement = try self.parseIf();
                            try statements.append(ast.Statement{ .if_statement = if_statement });
                        },
                        .@"return" => {
                            const return_statement = try self.parseReturn();
                            try statements.append(ast.Statement{ .simple_statement = return_statement });
                        },
                        else => {
                            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect statement, got {} at position {}", .{ token, self.lexer.pos() });
                            return Error.ParsingFailed;
                        },
                    }
                },
            }
        }
        return Error.ParsingFailed;
    }

    fn parseReturn(self: *Parser) !ast.SimpleStatement {
        const return_token = try self.lexer.next();
        if (return_token != .raw or return_token.raw.tag != RawToken.Tag.@"return") {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect return, got {} at position {}", .{ return_token, self.lexer.pos() });
            return null;
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

    fn parseExprStack(self: *Parser, first: ParseElement) !*ast.Expr {
        var binOpStack = std.ArrayList(ast.BinOp).init(self.allocator);
        var elementStack = std.ArrayList(ParseElement).init(self.allocator);
        defer binOpStack.deinit();
        defer elementStack.deinit();
        elementStack.append(first);
        while (true) {
            const token = try self.lexer.peek();
        }
    }

    fn parseExpr(self: *Parser) !*ast.Expr {
        const first_tok = try self.lexer.next();
        if (first_tok != .raw) {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect raw, got {} at position {}", .{ first_tok, self.lexer.pos() });
            return null;
        }
        const expr = try self.allocator.create(ast.Expr);
        switch (first_tok.raw.tag) {
            RawToken.Tag.identifier => {
                const maybe_paren = try self.lexer.peek();
                if (maybe_paren == .raw and maybe_paren.raw.tag == RawToken.Tag.l_paren) {
                    const args = self.parseFunctionArgs();
                    expr.function_call = ast.FunctionCall{
                        .args = args,
                        .name = self.code[first_tok.raw.loc.start..first_tok.raw.loc.end],
                    };
                    return expr;
                }

                expr.ident = self.code[first_tok.raw.loc.start..first_tok.raw.loc.end];
                return expr;
            },
            .int | .string | .true | .false | .none => {
                expr.@"const" = try self.parseConst(first_tok.raw);
                return expr;
            },
            RawToken.Tag.sub => {
                return ast.Expr{ .unary_expr = try parseExpr(self) };
            },
            RawToken.Tag.not => {
                return ast.Expr{ .not_expr = try parseExpr(self) };
            },
            RawToken.Tag.l_bracket => {
                var elements = std.ArrayList(*ast.Expr).init(self.allocator);
                while (true) {
                    try elements.append(try self.parseExpr());
                    const maybe_comma = try self.lexer.peek();
                    if (maybe_comma == .raw and maybe_comma.raw.tag == RawToken.Tag.comma) {
                        _ = try self.lexer.next();
                        continue;
                    }
                    if (maybe_comma == .raw and maybe_comma.raw.tag == RawToken.Tag.r_bracket) {
                        return ast.Expr{ .list_declare = elements };
                    }
                    self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect , or ], got {} at position {}", .{ maybe_comma, self.lexer.pos() });
                    return Error.ParsingFailed;
                }
            },
            RawToken.Tag.l_paren => {
                return ast.Expr{ .paren_expr = try parseExpr(self) };
            },
            else => {
                self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect expr, got {} at position {}", .{ first_tok, self.lexer.pos() });
                return Error.ParsingFailed;
            },
        }
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
        const if_token = try self.lexer.next();
        if (if_token != .raw or if_token.raw.tag != RawToken.Tag.@"if") {
            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect if, got {} at position {}", .{ if_token, self.lexer.pos() });
            return Error.ParsingFailed;
        }
        //todo
        return Error.ParsingFailed;
    }

    pub fn parse(self: *Parser) anyerror!ast.AstFile {
        var defs = std.ArrayList(ast.Def).init(self.allocator);
        const statements = std.ArrayList(ast.Statement).init(self.allocator);

        while (true) {
            const token = try self.lexer.peek();
            switch (token) {
                .new_line => {
                    continue;
                },
                .raw => |raw| {
                    switch (raw.tag) {
                        .def => {
                            const def = try self.parseDef();
                            try defs.append(def);
                        },
                        else => {
                            self.diagnostics = try std.fmt.allocPrint(self.allocator, "Expect def, got {} at position {}", .{ token, raw.loc.start });
                            return Error.ParsingFailed;
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

test "ww" {
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

    std.debug.print("{any}", .{ast_file});
}
