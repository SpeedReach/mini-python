const ast = @import("ast.zig");
const std = @import("std");

pub fn print_ast(out: std.io.AnyWriter, file: ast.AstFile) !void {
    for (file.defs.items) |def| {
        try print_def(out, def);
    }
    for (file.statements.items) |statement| {
        try print_statement(out, statement, 0);
    }
}
pub fn print_def(out: std.io.AnyWriter, def: ast.Def) !void {
    try out.print("def {s}(", .{def.name});
    //def a(b,c)
    for (def.params.items) |param| {
        try out.print("{s},", .{param});
    }
    try out.writeAll("): \n");
    for (def.body.statements.items) |statement| {
        try print_statement(out, statement, 1);
    }
}

pub fn print_statement(out: std.io.AnyWriter, statement: ast.Statement, indents: u8) !void {
    switch (statement) {
        ast.Statement.simple_statement => {
            try print_simple_statement(out, statement.simple_statement, indents);
        },
        ast.Statement.if_statement => {
            try out.writeByteNTimes(' ', indents * 2);
            try out.writeAll(
                "if ",
            );
            try print_expr(out, statement.if_statement.condition.*);
            try out.writeAll(":\n");
            for (statement.if_statement.body.statements.items) |child| {
                try print_statement(out, child, indents + 1);
            }
        },
        ast.Statement.if_else_statement => {
            try out.writeByteNTimes(' ', indents * 2);
            try out.writeAll("if ");
            try print_expr(out, statement.if_else_statement.condition.*);
            try out.writeAll(":\n");
            for (statement.if_else_statement.if_body.statements.items) |child| {
                try print_statement(out, child, indents + 1);
            }
            try out.writeByteNTimes(' ', indents * 2);
            try out.writeAll("else:\n");
            for (statement.if_else_statement.else_body.statements.items) |child| {
                try print_statement(out, child, indents + 1);
            }
        },
        ast.Statement.for_in_statement => {
            try out.writeByteNTimes(' ', indents * 2);
            try out.writeAll(
                "for ",
            );
            try out.writeAll(statement.for_in_statement.var_name);
            try out.writeAll(" in ");
            try print_expr(out, statement.for_in_statement.iterable.*);
            try out.writeAll(":\n");
            for (statement.for_in_statement.body.statements.items) |child| {
                try print_statement(out, child, indents + 1);
            }
        },
    }
}

pub fn print_expr(out: std.io.AnyWriter, expr: ast.Expr) !void {
    try out.writeAll("(");
    switch (expr) {
        ast.ExprTag.ident => {
            try out.writeAll(expr.ident);
        },
        ast.ExprTag.@"const" => |cnst| {
            switch (cnst) {
                ast.ConstTag.int => {
                    try out.print("{d}", .{cnst.int});
                },
                ast.ConstTag.boolean => {
                    try out.print("{s}", .{if (cnst.boolean) "True" else "False"});
                },
                ast.ConstTag.none => {
                    try out.writeAll("None");
                },
                ast.ConstTag.string => {
                    try out.print("{s}", .{cnst.string});
                },
            }
        },
        ast.ExprTag.bin_op => {
            try print_expr(out, expr.bin_op.lhs.*);
            try out.writeAll(" ");
            try out.print("{s}", .{@tagName(expr.bin_op.op)});
            try out.writeAll(" ");
            try print_expr(out, expr.bin_op.rhs.*);
        },
        ast.ExprTag.function_call => {
            try out.writeAll(expr.function_call.name);
            try out.writeAll("(");
            for (expr.function_call.args.items) |arg| {
                try print_expr(out, arg.*);
                try out.writeAll(", ");
            }
            try out.writeAll(")");
        },
        else => {},
    }
    try out.writeAll(")");
}

pub fn print_simple_statement(out: std.io.AnyWriter, statement: ast.SimpleStatement, indents: u8) !void {
    try out.writeByteNTimes(' ', indents * 2);
    switch (statement) {
        ast.SimpleStatementTag.assign => {
            try out.print("{s}", .{statement.assign.lhs});
            try out.writeAll(" = ");
            try print_expr(out, statement.assign.rhs.*);
            try out.writeAll("\n");
        },
        ast.SimpleStatementTag.assign_list => {
            try print_expr(out, statement.assign_list.lhs.*);
            try out.writeAll("[");
            try print_expr(out, statement.assign_list.idx.*);
            try out.writeAll("] = ");
            try print_expr(out, statement.assign_list.rhs.*);
            try out.writeAll("\n");
        },
        ast.SimpleStatementTag.print => {
            try out.writeAll("print(");
            try print_expr(out, statement.print.value.*);
            try out.writeAll(")\n");
        },
        ast.SimpleStatementTag.expr => {
            try print_expr(out, statement.expr.*);
            try out.writeAll("\n");
        },
        ast.SimpleStatementTag.@"return" => {
            try out.writeAll("return ");
            try print_expr(out, statement.@"return".*);
            try out.writeAll("\n");
        },
    }
}
