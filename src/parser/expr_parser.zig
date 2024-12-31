const ast = @import("../ast/ast.zig");
const lex = @import("../lexer/lexer.zig");
const std = @import("std");

const ParserElement = union(enum) {
    expr: ast.Expr,
    ident: []const u8,
    comma,
    l_paren,
    l_bracket,
    bin_op,
};

const RawToken = @import("../lexer/token.zig").RawToken;
const RawTokenTag = RawToken.Tag;

pub const Error = error{ InvalidToken, InvalidState };

pub const ExprParser = struct {
    lexer: *lex.Lexer,
    allocator: std.mem.Allocator,
    code: [:0]const u8,

    pub fn init(allocator: std.mem.Allocator, lexer: *lex.Lexer) ExprParser {
        return ExprParser{ .lexer = lexer, .code = lexer.tokenizer.buffer, .allocator = allocator };
    }

    fn parse_primary(self: *ExprParser) anyerror!ast.Expr {
        const token = try self.lexer.next();
        if (token != .raw) {
            return Error.InvalidToken;
        }
        const raw = token.raw;
        switch (raw.tag) {
            RawTokenTag.identifier => {
                const ident = self.code[raw.loc.start..raw.loc.end];
                const maybe_paren = try self.lexer.peek();
                if (maybe_paren != .raw or maybe_paren.raw.tag != RawTokenTag.l_paren) {
                    return ast.Expr{ .ident = ident };
                }
                try self.eat();
                const args = try self.parse_expr_list();
                try self.eat_expect(RawTokenTag.r_paren);
                return ast.Expr{ .function_call = ast.FunctionCall{ .name = ident, .args = args } };
            },
            RawTokenTag.string => {
                return ast.Expr{ .@"const" = ast.Const{
                    .string = self.code[raw.loc.start + 1 .. raw.loc.end - 1],
                } };
            },
            RawTokenTag.int => {
                const int = try std.fmt.parseInt(i64, self.code[raw.loc.start..raw.loc.end], 10);
                return ast.Expr{
                    .@"const" = ast.Const{ .int = int },
                };
            },
            RawTokenTag.l_paren => {
                const inner = try self.parse(0);
                try self.eat_expect(RawTokenTag.r_paren);
                return inner;
            },
            RawTokenTag.l_bracket => {
                const values = try self.parse_expr_list();
                try self.eat_expect(RawTokenTag.r_bracket);
                return ast.Expr{ .list_declare = ast.ListDeclare{ .values = values } };
            },
            RawTokenTag.not => {
                const inner = try self.parse(3);
                const inner_expr = try self.allocator.create(ast.Expr);
                inner_expr.* = inner;
                return ast.Expr{ .not_expr = inner_expr };
            },
            RawTokenTag.sub => {
                const inner = try self.allocator.create(ast.Expr);
                inner.* = try self.parse(7);
                return ast.Expr{ .unary_expr = inner };
            },
            else => {
                std.debug.print("unexpected token: {} at {d}\n", .{ raw.tag, self.lexer.pos() });
                return Error.InvalidToken;
            },
        }
    }

    fn parse_expr_list(self: *ExprParser) !std.ArrayList(*ast.Expr) {
        var args = std.ArrayList(*ast.Expr).init(self.allocator);
        const first = try self.lexer.peek();
        if (first == .raw and first.raw.tag == RawTokenTag.r_paren) {
            return args;
        }
        while (true) {
            const expr = try self.allocator.create(ast.Expr);
            expr.* = try self.parse(0);
            try args.append(expr);
            const maybe_comma = try self.lexer.peek();
            if (maybe_comma != .raw or maybe_comma.raw.tag != RawTokenTag.comma) {
                break;
            }
            try self.eat();
        }
        return args;
    }

    fn eat(self: *ExprParser) !void {
        _ = try self.lexer.next();
    }

    fn eat_expect(self: *ExprParser, expected: RawTokenTag) !void {
        const token = try self.lexer.next();
        if (token != .raw) {
            return Error.InvalidToken;
        }
        if (token.raw.tag != expected) {
            return Error.InvalidToken;
        }
    }

    pub fn parse(self: *ExprParser, min_precedence: i16) !ast.Expr {
        var left = try self.parse_primary();
        // handle list access
        while (true) {
            const maybe_l_bracket = try self.lexer.peek();
            if (maybe_l_bracket != .raw or maybe_l_bracket.raw.tag != RawTokenTag.l_bracket) {
                break;
            }
            try self.eat();
            const index = try self.parse(0);
            try self.eat_expect(RawTokenTag.r_bracket);
            const list = try self.allocator.create(ast.Expr);
            list.* = left;
            const indexExpr = try self.allocator.create(ast.Expr);
            indexExpr.* = index;
            left = ast.Expr{ .list_access = ast.ListAccess{ .list = list, .idx = indexExpr } };
        }
        // handle binary operators
        while (true) {
            const token = try self.lexer.peek();
            if (token != .raw) {
                break;
            }
            const tag = token.raw.tag;
            const precedence = getPrecedence(tag);
            if (precedence < min_precedence) {
                break;
            }
            try self.eat();
            const right = try self.parse(precedence + 1);
            const left_expr = try self.allocator.create(ast.Expr);
            left_expr.* = left;
            const right_expr = try self.allocator.create(ast.Expr);
            right_expr.* = right;

            left = ast.Expr{ .bin_op = ast.BinOpExpr{ .lhs = left_expr, .op = token2BinOp(tag), .rhs = right_expr } };
        }
        return left;
    }
};

fn token2BinOp(token: RawTokenTag) ast.BinOp {
    switch (token) {
        RawTokenTag.add => return ast.BinOp.add,
        RawTokenTag.sub => return ast.BinOp.sub,
        RawTokenTag.mul => return ast.BinOp.mul,
        RawTokenTag.div => return ast.BinOp.div,
        RawTokenTag.percent => return ast.BinOp.div,
        RawTokenTag.equal_equal => return ast.BinOp.eq,
        RawTokenTag.ne => return ast.BinOp.ne,
        RawTokenTag.lt => return ast.BinOp.lt,
        RawTokenTag.le => return ast.BinOp.le,
        RawTokenTag.gt => return ast.BinOp.gt,
        RawTokenTag.ge => return ast.BinOp.ge,
        RawTokenTag.@"and" => return ast.BinOp.@"and",
        RawTokenTag.@"or" => return ast.BinOp.@"or",
        else => unreachable,
    }
}

fn getPrecedence(token: RawTokenTag) i16 {
    switch (token) {
        RawTokenTag.@"or" => return 1,
        RawTokenTag.@"and" => return 2,
        RawTokenTag.ge, RawTokenTag.gt, RawTokenTag.le, RawTokenTag.lt, RawTokenTag.equal_equal, RawTokenTag.ne => return 3,
        RawTokenTag.add, RawTokenTag.sub => return 4,
        RawTokenTag.mul, RawTokenTag.div, RawTokenTag.percent => return 5,
        else => return -1,
    }
}

const testing = std.testing;
test "a+b" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "a+b");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqualStrings(expr.bin_op.lhs.ident, "a");
    try testing.expectEqual(expr.bin_op.op, ast.BinOp.add);
    try testing.expectEqualStrings(expr.bin_op.rhs.ident, "b");
}

test "a+b*c" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "a+b*c");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqualStrings(expr.bin_op.lhs.ident, "a");
    try testing.expectEqual(expr.bin_op.op, ast.BinOp.add);
    const bMulc = expr.bin_op.rhs;
    try testing.expectEqualStrings(bMulc.bin_op.lhs.ident, "b");
    try testing.expectEqual(bMulc.bin_op.op, ast.BinOp.mul);
    try testing.expectEqualStrings(bMulc.bin_op.rhs.ident, "c");
}

test "(a+bddd)*c" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "(a+bddd)*c");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    const aPlusb = expr.bin_op.lhs;
    try testing.expectEqualStrings(aPlusb.bin_op.lhs.ident, "a");
    try testing.expectEqual(aPlusb.bin_op.op, ast.BinOp.add);
    try testing.expectEqualStrings("bddd", aPlusb.bin_op.rhs.ident);
    try testing.expectEqual(expr.bin_op.op, ast.BinOp.mul);
    try testing.expectEqualStrings(expr.bin_op.rhs.ident, "c");
}

test "a[b]" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "a[b]");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqualStrings(expr.list_access.list.ident, "a");
    try testing.expectEqualStrings(expr.list_access.idx.ident, "b");
}

test "a[b][c]" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "a[b][c]");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqualStrings("c", expr.list_access.idx.ident);
    const a_b = expr.list_access.list;
    try testing.expectEqualStrings("b", a_b.list_access.idx.ident);
    try testing.expectEqualStrings("a", a_b.list_access.list.ident);
}

test "a or b" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "a or b");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqual(expr.bin_op.op, ast.BinOp.@"or");
    try testing.expectEqualStrings(expr.bin_op.lhs.ident, "a");
    try testing.expectEqualStrings(expr.bin_op.rhs.ident, "b");
}

test "f(b)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "f(b)");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqualStrings(expr.function_call.name, "f");
    try testing.expectEqualStrings(expr.function_call.args.items[0].ident, "b");
}

test "f(b, c)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "f(b, c)");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqualStrings(expr.function_call.name, "f");
    try testing.expectEqualStrings(expr.function_call.args.items[0].ident, "b");
    try testing.expectEqualStrings(expr.function_call.args.items[1].ident, "c");
}

test "f(b+c, d)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "f(b+c, d)");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqualStrings(expr.function_call.name, "f");
    try testing.expectEqual(expr.function_call.args.items[0].bin_op.op, ast.BinOp.add);
    try testing.expectEqualStrings(expr.function_call.args.items[0].bin_op.lhs.ident, "b");
    try testing.expectEqualStrings(expr.function_call.args.items[0].bin_op.rhs.ident, "c");
    try testing.expectEqualStrings(expr.function_call.args.items[1].ident, "d");
}

test "a + b * c or d // e[2][4] + f" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "a + b * c or d // e[2][4] + f");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqual(ast.BinOp.@"or", expr.bin_op.op);

    const or_left = expr.bin_op.lhs;
    try testing.expectEqualStrings("a", or_left.bin_op.lhs.ident);
    try testing.expectEqual(ast.BinOp.add, or_left.bin_op.op);
    const or_left_right = or_left.bin_op.rhs;
    try testing.expectEqualStrings("b", or_left_right.bin_op.lhs.ident);
    try testing.expectEqual(ast.BinOp.mul, or_left_right.bin_op.op);
    try testing.expectEqualStrings("c", or_left_right.bin_op.rhs.ident);

    const or_right = expr.bin_op.rhs;
    try testing.expectEqual(ast.BinOp.add, or_right.bin_op.op);
    const or_right_left = or_right.bin_op.lhs;
    try testing.expectEqual(ast.BinOp.div, or_right_left.bin_op.op);
    try testing.expectEqualStrings("d", or_right_left.bin_op.lhs.ident);
    try testing.expectEqualStrings("f", or_right.bin_op.rhs.ident);

    const or_r_l_r = or_right_left.bin_op.rhs;
    try testing.expect(or_r_l_r.list_access.idx.@"const".int == 4);
    const or_r_ll = or_r_l_r.list_access.list;
    try testing.expect(or_r_ll.list_access.idx.@"const".int == 2);
    try testing.expectEqualStrings("e", or_r_ll.list_access.list.ident);
}

test "1" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "1");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqual(1, expr.@"const".int);
}
test "string literal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator,
        \\"hello"
    );
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqualStrings("hello", expr.@"const".string);
}

test "string lt add" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "\"hello\" + \"world\"");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqual(ast.BinOp.add, expr.bin_op.op);
    try testing.expectEqualStrings("hello", expr.bin_op.lhs.@"const".string);
    try testing.expectEqualStrings("world", expr.bin_op.rhs.@"const".string);
}

test "w()" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var lexer = lex.Lexer.init(allocator, "w()");
    var parser = ExprParser.init(allocator, &lexer);
    const expr = try parser.parse(0);
    try testing.expectEqualStrings("w", expr.function_call.name);
    try testing.expectEqual(0, expr.function_call.args.items.len);
}
