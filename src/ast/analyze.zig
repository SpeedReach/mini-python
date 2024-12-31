const ast = @import("./ast.zig");
const std = @import("std");

pub const Variable = []const u8;

pub const ScopeContext = struct {
    vars: std.ArrayList(Variable),

    pub fn deinit(self: *ScopeContext) void {
        self.vars.deinit();
    }
};

pub const Error = error{
    IdentConflict,
    UndefinedFunction,
    WrongNumberOfArgs,
};

pub const AnalyzedFunction = struct {
    name: []const u8,
    args: std.ArrayList(Variable),
    context: ScopeContext,
};

pub const Analyzer = struct {
    allocator: std.mem.Allocator,
    ast_file: ast.AstFile,
    global_vars: std.ArrayList(Variable),
    functions: std.AutoHashMap([]const u8, AnalyzedFunction),
    result: []const u8,

    pub fn init(allocator: std.mem.Allocator, ast_file: ast.AstFile) Analyzer {
        return Analyzer{
            .allocator = allocator,
            .ast_file = ast_file,
            .global_vars = std.ArrayList(Variable).init(allocator),
            .function_contexts = std.AutoHashMap([]const u8, AnalyzedFunction).init(allocator),
            .result = "",
        };
    }

    pub fn deinit(self: *Analyzer) void {
        self.global_context.vars.deinit();
        for (self.function_contexts.items) |context| {
            context.deinit();
        }
    }

    pub fn analyze(self: *Analyzer) !void {
        try self.addBuiltIn("print", 1);
        try self.addBuiltIn("list", 1);
        try self.addBuiltIn("range", 1);
        try self.addBuiltIn("len", 1);

        for (self.ast_file.defs.items) |def| {
            self.analyzeDef(def);
        }
    }

    fn addBuiltIn(self: *Analyzer, name: []const u8, args_len: u8) !void {
        var func = AnalyzedFunction{
            .name = name,
            .args = std.ArrayList(Variable).init(self.allocator),
            .context = ScopeContext{
                .vars = std.ArrayList(Variable).init(self.allocator),
            },
        };
        for (0..args_len) |_| {
            try func.args.append("a");
        }
        try self.functions.put(
            name,
        );
    }

    pub fn analyzeDef(self: *Analyzer, def: ast.Def) !void {
        const conflict = self.functions.get(def.name);
        if (conflict != null) {
            return Error.IdentConflict;
        }

        var arg_names = std.AutoHashMap([]const u8, void).init(self.allocator);
        defer arg_names.deinit();
        for (def.params.items) |param| {
            const conflict_arg = arg_names.get(param);
            if (conflict_arg != null) {
                return Error.IdentConflict;
            }
            arg_names.put(param, null);
        }
        var context = ScopeContext{
            .vars = std.ArrayList([]const u8).init(self.allocator),
        };
        try self.functions.put(def.name, AnalyzedFunction{
            .name = def.name,
            .args = def.params,
            .context = context,
        });
        try self.analyzeStatements(def.body, &context);
        try self.functions.put(def.name, AnalyzedFunction{
            .name = def.name,
            .args = def.params,
            .context = context,
        });
    }

    pub fn analyzeStatements(self: *Analyzer, statements: std.ArrayList(ast.Statement), context: *ScopeContext) !void {
        for (statements.items) |statement| {
            switch (statement) {
                ast.StatementTag.if_statement => |if_statement| {
                    try self.analyzeExpr(if_statement.condition, context);
                    try self.analyzeStatements(if_statement.body, context);
                },
                ast.StatementTag.if_else_statement => |if_else_statement| {
                    try self.analyzeExpr(if_else_statement.condition, context);
                    try self.analyzeStatements(if_else_statement.if_body, context);
                    try self.analyzeStatements(if_else_statement.else_body, context);
                },
                else => {},
            }
        }
    }

    pub fn analyzeExpr(self: *Analyzer, expr: *ast.Expr, context: *ScopeContext) !void {
        switch (expr.*) {
            ast.ExprTag.function_call => |function_call| {
                const function = self.functions.get(function_call.name);
                if (function == null) {
                    return Error.UndefinedFunction;
                }
                if (function.args.items.len != function_call.args.items.len) {
                    return Error.WrongNumberOfArgs;
                }
                for (function.args.items) |arg| {
                    try self.analyzeExpr(arg, context);
                }
            },
            ast.ExprTag.bin_op => |bin_op| {
                try self.analyzeExpr(bin_op.lhs, context);
                try self.analyzeExpr(bin_op.rhs, context);
            },
            ast.ExprTag.list_access => |list_access| {
                try self.analyzeExpr(list_access.list, context);
                try self.analyzeExpr(list_access.idx, context);
            },
            else => {},
        }
    }
};
