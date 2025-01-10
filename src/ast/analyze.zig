const ast = @import("./ast.zig");
const std = @import("std");
const ds = @import("../ds/set.zig");

pub const Error = error{ IdentConflict, UndefinedFunction, WrongNumberOfArgs, ListShouldFollowRange, UndefinedVariable };

pub const Context = struct {
    assigned_vars: std.StringHashMap(void),
};

pub const AnalyzedFunction = struct {
    context: Context,
    name: []const u8,
    arg_num: usize,
};

pub const Analyzer = struct {
    allocator: std.mem.Allocator,
    functions: std.StringHashMap(AnalyzedFunction),
    result: []const u8,
    main_context: Context,
    pub fn init(allocator: std.mem.Allocator) Analyzer {
        return Analyzer{
            .allocator = allocator,
            .functions = std.StringHashMap(AnalyzedFunction).init(allocator),
            .result = "",
            .main_context = Context{ .assigned_vars = std.StringHashMap(void).init(allocator) },
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

        try findAssignedVars(ast_file.statements, &self.main_context.assigned_vars);
        for (ast_file.defs.items) |def| {
            var context = Context{
                .assigned_vars = std.StringHashMap(void).init(self.allocator),
            };
            try findAssignedVars(def.body.statements, &context.assigned_vars);
            try self.analyzeDef(def, &context);
        }
        try self.analyzeStatements(ast_file.statements, self.main_context);
    }

    fn addBuiltIn(self: *Analyzer, name: []const u8, arg_num: u8) !void {
        const func = AnalyzedFunction{ .name = name, .arg_num = arg_num, .context = Context{ .assigned_vars = undefined } };

        try self.functions.put(name, func);
    }

    pub fn analyzeDef(self: *Analyzer, def: ast.Def, context: *Context) !void {
        const conflict = self.functions.get(def.name);
        if (conflict != null) {
            return Error.IdentConflict;
        }

        var arg_names = std.StringHashMap(void).init(self.allocator);
        defer arg_names.deinit();
        for (def.params.items) |param| {
            if (arg_names.contains(param)) {
                return Error.IdentConflict;
            }
            try context.assigned_vars.put(param, void{});
            try arg_names.put(param, void{});
        }
        try self.functions.put(def.name, AnalyzedFunction{
            .name = def.name,
            .arg_num = def.params.items.len,
            .context = context.*,
        });
        try self.analyzeStatements(def.body.statements, context.*);
    }

    pub fn analyzeStatements(self: *Analyzer, statements: std.ArrayList(ast.Statement), context: Context) !void {
        for (statements.items) |statement| {
            switch (statement) {
                ast.StatementTag.if_statement => |if_statement| {
                    try self.analyzeExpr(if_statement.condition, context);
                    try self.analyzeStatements(if_statement.body.statements, context);
                },
                ast.StatementTag.if_else_statement => |if_else_statement| {
                    try self.analyzeExpr(if_else_statement.condition, context);
                    try self.analyzeStatements(if_else_statement.if_body.statements, context);
                    try self.analyzeStatements(if_else_statement.else_body.statements, context);
                },
                ast.StatementTag.for_in_statement => |for_in_statement| {
                    try self.analyzeExpr(for_in_statement.iterable, context);
                    try self.analyzeStatements(for_in_statement.body.statements, context);
                },
                ast.StatementTag.simple_statement => {
                    const simple_statement = statement.simple_statement;
                    switch (simple_statement) {
                        ast.SimpleStatementTag.@"return" => |return_statement| {
                            try self.analyzeExpr(return_statement, context);
                        },
                        ast.SimpleStatementTag.assign => |assign| {
                            try self.analyzeExpr(assign.rhs, context);
                        },
                        ast.SimpleStatementTag.assign_list => |assign_list| {
                            try self.analyzeExpr(assign_list.lhs, context);
                            try self.analyzeExpr(assign_list.idx, context);
                            try self.analyzeExpr(assign_list.rhs, context);
                        },
                        ast.SimpleStatementTag.print => |print| {
                            try self.analyzeExpr(print.value, context);
                        },
                        ast.SimpleStatementTag.expr => |expr| {
                            try self.analyzeExpr(expr, context);
                        },
                    }
                },
            }
        }
    }

    pub fn analyzeExpr(self: *Analyzer, expr: *ast.Expr, context: Context) !void {
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
                    try self.analyzeExpr(arg, context);
                }

                if (std.mem.eql(u8, "list", function_call.name)) {
                    const arg: *ast.Expr = function_call.args.items[0];
                    if (arg.* != .function_call) {
                        return Error.ListShouldFollowRange;
                    }
                    if (!std.mem.eql(u8, "range", arg.*.function_call.name)) {
                        return Error.ListShouldFollowRange;
                    }
                }
            },
            ast.ExprTag.bin_op => |bin_op| {
                try self.analyzeExpr(bin_op.lhs, context);
                try self.analyzeExpr(bin_op.rhs, context);
            },
            ast.ExprTag.unary_expr => |unary_expr| {
                try self.analyzeExpr(unary_expr, context);
            },
            ast.ExprTag.not_expr => |not_expr| {
                try self.analyzeExpr(not_expr, context);
            },
            ast.ExprTag.ident => |ident| {
                if ((!context.assigned_vars.contains(ident)) and (!self.main_context.assigned_vars.contains(ident))) {
                    return Error.UndefinedVariable;
                }
            },
            ast.ExprTag.@"const" => {},
            ast.ExprTag.list_declare => |list_declare| {
                for (list_declare.values.items) |item| {
                    try self.analyzeExpr(item, context);
                }
            },
            ast.ExprTag.list_access => |list_access| {
                try self.analyzeExpr(list_access.list, context);
                try self.analyzeExpr(list_access.idx, context);
            },
        }
    }
};

pub fn findAssignedVars(statements: std.ArrayList(ast.Statement), dest: *std.StringHashMap(void)) !void {
    for (statements.items) |statement| {
        switch (statement) {
            .for_in_statement => {
                try dest.put(statement.for_in_statement.var_name, void{});
                try findAssignedVars(statement.for_in_statement.body.statements, dest);
            },
            .if_else_statement => {
                try findAssignedVars(statement.if_else_statement.if_body.statements, dest);
                try findAssignedVars(statement.if_else_statement.else_body.statements, dest);
            },
            .if_statement => {
                try findAssignedVars(statement.if_statement.body.statements, dest);
            },
            .simple_statement => {
                try findStatementAssignedVars(statement.simple_statement, dest);
            },
        }
    }
}

fn findStatementAssignedVars(ss: ast.SimpleStatement, dest: *std.StringHashMap(void)) !void {
    switch (ss) {
        .assign => {
            try dest.put(ss.assign.lhs, void{});
        },
        else => {},
    }
}
