const std = @import("std");
const ast = @import("../ast/ast.zig");
pub const x86_64 = @import("./x86_64.zig");

pub const CodeGenerator = struct {
    allocator: std.mem.Allocator,
    globalVars: std.AutoHashMap([]u8, void),
    // name, rsb offset
    scopeVars: std.AutoHashMap([]u8, u32),

    pub fn init(allocator: std.mem.Allocator) CodeGenerator {
        return CodeGenerator{ .allocator = allocator };
    }

    pub fn emit(self: *CodeGenerator, builder: *x86_64.Builder, tree: ast.AstFile) !void {
        emitMalloc(builder);
        for (tree.statements) |statement| {
            try self.emitStatement(builder, statement);
        }
    }

    pub fn emitStatement(self: *CodeGenerator, builder: *x86_64.Builder, statement: ast.Statement, topLevel: bool) !void {
        switch (statement) {
            ast.StatementTag.simple_statement => {
                try self.emitSimpleStatement(builder, statement.simple_statement, topLevel);
            },
            else => {},
        }
        return;
    }

    pub fn emitSimpleStatement(self: *CodeGenerator, builder: *x86_64.Builder, statement: ast.SimpleStatement, topLevel: bool) !void {
        switch (statement) {
            ast.SimpleStatementTag.assign => {
                try self.emitSimpleAssignment(builder, statement.assign, topLevel);
            },
            ast.SimpleStatementTag.print => {},
            else => {},
        }
        return;
    }

    pub fn emitSimpleAssignment(self: *CodeGenerator, builder: *x86_64.Builder, assignment: ast.SimpleAssignment, topLevel: bool) !void {
        if (topLevel) {
            builder.bss(assignment.lhs, 8);
        }
    }
    pub fn emitExpr(self: *CodeGenerator, builder: *x86_64.Builder, expr: ast.Expr) !void {
        switch (expr) {
            ast.ExprTag.@"const" => {
                try self.emitConst(builder, expr.value);
            },
            ast.BinOpExpr => {
                try self.emitBinOp(builder, expr.value);
            },
            else => {},
        }
        return;
    }

    pub fn emitBinOp(self: *CodeGenerator, builder: *x86_64.Builder, binOp: ast.BinOpExpr) !void {
        try self.emitExpr(builder, binOp.lhs);
        try self.emitExpr(builder, binOp.rhs);

        switch (binOp.op) {
            .add => {},
            else => {},
        }
    }

    pub fn emitConst(_: *CodeGenerator, builder: *x86_64.Builder, c: ast.Const) !void {
        switch (c) {
            ast.Type.Int => {
                emitAllocInt(builder, c.int);
            },
            else => {},
        }
        return;
    }
};

//Adds the pop and add the top 2 values on the stack and pushes the result
fn emitAdd(builder: *x86_64.Builder) !void {
    builder.popq(x86_64.rdi);
    builder.popq(x86_64.rsi);
    builder.movq(x86_64.IndirectMemory{
        .base = x86_64.rdi,
        .offset = 0,
    }, x86_64.rcx);
    builder.movq(x86_64.IndirectMemory{
        .base = x86_64.rsi,
        .offset = 0,
    }, x86_64.rdx);

    builder.cmpq(x86_64.rcx, x86_64.rdx);
    builder.jne("runtime_panic");
    builder.cmpq(0, x86_64.rcx);
    builder.je("runtime_panic");
    builder.cmpq(1, x86_64.rcx);
    builder.je("")
}

//Allocates 16 bytes on the heap and stores the value in the first 8 bytes
fn emitAllocInt(builder: *x86_64.Builder, value: i64) !void {
    emitCallMalloc(builder, 16);
    //set value
    builder.movq(value, x86_64.IndirectMemory{ .base = x86_64.rax, .offset = 0 });
    //store pointer on stack
    builder.subq(8, x86_64.rsp);
    builder.movq(x86_64.rax, x86_64.IndirectMemory{ .base = x86_64.rsp, .offset = 0 });
}

// rax = malloc ptr
fn emitCallMalloc(builder: *x86_64.Builder, size: u32) !void {
    builder.subq(8, x86_64.rsp);
    builder.movq(size, x86_64.IndirectMemory{ .base = x86_64.rbp, .offset = 0 });
    builder.call("my_malloc");
    builder.addq(8, x86_64.rsp);
}

fn emitMalloc(builder: *x86_64.Builder) !void {
    builder.label("my_malloc");
    builder.pushq(x86_64.rbp);
    builder.movq(x86_64.rsp, x86_64.rbp);
    builder.andq(-16, x86_64.rsp);
    builder.movq(x86_64.IndirectMemory{ .base = x86_64.rbp, .offset = 16 }, x86_64.rdi);
    builder.call("malloc");
    builder.movq(x86_64.rbp, x86_64.rsp);
    builder.popq(x86_64.rbp);
    builder.ret();
}

const testing = std.testing;

test "expr" {

    // a = 1 + 3
    // print(1+3)

    const tree = ast.AstFile{
        .defs = &[_]ast.Def{},
        .statements = &[_]ast.Statement{ast.Statement{ .simple_statement = ast.SimpleStatement{ .print = ast.Print{ .value = &ast.Expr{
            .ident = "abc",
        } } } }},
    };

    var codeGen = CodeGenerator{
        .allocator = testing.allocator,
    };

    var program = x86_64.Program.init(testing.allocator);
    var builder = x86_64.Builder.init(&program);
    try codeGen.emit(&builder, tree);
    var formatter = x86_64.Formatter(std.fs.File.Writer).init(std.io.getStdErr().writer());
    try formatter.writeProgram(program);
}
