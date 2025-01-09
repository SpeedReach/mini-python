const ast = @import("./ast.zig");
const std = @import("std");

pub const Error = error{
    IdentConflict,
    UndefinedFunction,
    WrongNumberOfArgs,
};

pub const AnalyzedFunction = struct {
    name: []const u8,
    arg_num: usize,
};

pub const Analyzer = struct {
    allocator: std.mem.Allocator,

    functions: std.StringHashMap(AnalyzedFunction),
    result: []const u8,

    pub fn init(allocator: std.mem.Allocator) Analyzer {
        return Analyzer{
            .allocator = allocator,
            .functions = std.StringHashMap(AnalyzedFunction).init(allocator),
            .result = "",
        };
    }

    pub fn deinit(self: *Analyzer) void {
        self.global_context.vars.deinit();
        for (self.functions.items) |context| {
            context.deinit();
        }
    }

    pub fn analyze(self: *Analyzer, ast_file: ast.AstFile) !void {
        try self.addBuiltIn("print", 1);
        try self.addBuiltIn("list", 1);
        try self.addBuiltIn("range", 1);
        try self.addBuiltIn("len", 1);

        for (ast_file.defs.items) |def| {
            try self.analyzeDef(def);
        }
    }

    fn addBuiltIn(self: *Analyzer, name: []const u8, arg_num: u8) !void {
        const func = AnalyzedFunction{ .name = name, .arg_num = arg_num };

        try self.functions.put(name, func);
    }

    pub fn analyzeDef(self: *Analyzer, def: ast.Def) !void {
        const conflict = self.functions.get(def.name);
        if (conflict != null) {
            return Error.IdentConflict;
        }

        try self.functions.put(def.name, AnalyzedFunction{
            .name = def.name,
            .arg_num = def.params.items.len,
        });
        try self.analyzeStatements(def.body.statements);
    }

    pub fn analyzeStatements(self: *Analyzer, statements: std.ArrayList(ast.Statement)) !void {
        for (statements.items) |statement| {
            switch (statement) {
                ast.StatementTag.if_statement => |if_statement| {
                    try self.analyzeExpr(if_statement.condition);
                    try self.analyzeStatements(if_statement.body.statements);
                },
                ast.StatementTag.if_else_statement => |if_else_statement| {
                    try self.analyzeExpr(if_else_statement.condition);
                    try self.analyzeStatements(if_else_statement.if_body.statements);
                    try self.analyzeStatements(if_else_statement.else_body.statements);
                },
                ast.StatementTag.for_in_statement => |for_in_statement| {
                    try self.analyzeExpr(for_in_statement.iterable);
                    try self.analyzeStatements(for_in_statement.body.statements);
                },
                ast.StatementTag.simple_statement => {
                    const simple_statement = statement.simple_statement;
                    switch (simple_statement) {
                        ast.SimpleStatementTag.@"return" => |return_statement| {
                            try self.analyzeExpr(return_statement);
                        },
                        ast.SimpleStatementTag.assign => |assign| {
                            try self.analyzeExpr(assign.rhs);
                        },
                        ast.SimpleStatementTag.assign_list => |assign_list| {
                            try self.analyzeExpr(assign_list.lhs);
                            try self.analyzeExpr(assign_list.idx);
                            try self.analyzeExpr(assign_list.rhs);
                        },
                        ast.SimpleStatementTag.print => |print| {
                            try self.analyzeExpr(print.value);
                        },
                        ast.SimpleStatementTag.expr => |expr| {
                            try self.analyzeExpr(expr);
                        },
                    }
                },
            }
        }
    }

    pub fn analyzeExpr(self: *Analyzer, expr: *ast.Expr) !void {
        switch (expr.*) {
            ast.ExprTag.function_call => |function_call| {
                const function = self.functions.get(function_call.name);
                if (function == null) {
                    return Error.UndefinedFunction;
                }
                if (function.?.arg_num != function_call.args.items.len) {
                    return Error.WrongNumberOfArgs;
                }
                for (function_call.args.items) |arg| {
                    try self.analyzeExpr(arg);
                }
            },
            ast.ExprTag.bin_op => |bin_op| {
                try self.analyzeExpr(bin_op.lhs);
                try self.analyzeExpr(bin_op.rhs);
            },
            ast.ExprTag.unary_expr => |unary_expr| {
                try self.analyzeExpr(unary_expr);
            },
            ast.ExprTag.not_expr => |not_expr| {
                try self.analyzeExpr(not_expr);
            },
            ast.ExprTag.ident, ast.ExprTag.@"const" => {},
            ast.ExprTag.list_declare => |list_declare| {
                for (list_declare.values.items) |item| {
                    try self.analyzeExpr(item);
                }
            },
            ast.ExprTag.list_access => |list_access| {
                try self.analyzeExpr(list_access.list);
                try self.analyzeExpr(list_access.idx);
            },
        }
    }
};
