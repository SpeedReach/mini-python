const std = @import("std");
pub const Size = enum {
    Q,
};

pub const OperandTag = enum {
    Register,
    Immediate,
    IndirectMemory,
};

pub const Operand = union(OperandTag) {
    Register: Register,
    Immediate: i64,
    IndirectMemory: IndirectMemory,
};

pub const Register = struct {
    name: []const u8,
    size: Size,
};

pub const IndirectMemory = struct {
    base: Register,
    offset: i64,
};

pub const Program = struct {
    bss: std.io.AnyWriter,
    data: std.io.AnyWriter,
    text: std.io.AnyWriter,
};

pub const OperandError = error{
    TooManyIndirectOperands,
};

pub const Builder = struct {
    program: *Program,

    pub fn init(writer: std.io.Writer) Builder {
        return Builder{ .writer = writer };
    }

    pub fn start(self: *Builder) !void {
        std.debug.print("start", .{self});
    }

    pub fn subq(self: *Builder, value: Operand, reg: Operand) !void {
        const value_is_indirect = @as(OperandTag, value) == .Indirect;
        const reg_is_indirect = @as(OperandTag, reg) == .Indirect;
        if (value_is_indirect and reg_is_indirect) {
            return OperandError.TooManyIndirectOperands;
        }
        std.debug.print("subq", .{ self, value, reg });
    }

    pub fn label(self: *Builder, name: []const u8) !void {
        std.debug.print("label", .{ self, name });
    }

    pub fn ret(self: *Builder) !void {
        std.debug.print("ret", .{self});
    }

    pub fn pushq(self: *Builder, reg: Register) !void {
        std.debug.print("pushq", .{ self, reg });
    }

    pub fn addq(self: *Builder, value: Operand, reg: Operand) !void {
        std.debug.print("addq", .{ self, value, reg });
    }

    pub fn andq(self: *Builder, value: Operand, reg: Operand) !void {
        std.debug.print("andq", .{ self, value, reg });
    }

    pub fn popq(self: *Builder, reg: Register) !void {
        std.debug.print("popq", .{ self, reg });
    }

    pub fn bss(self: *Builder, name: []const u8, size: usize) !void {
        std.debug.print("bss", .{ self, name, size });
    }

    pub fn call(self: *Builder, name: []const u8) !void {
        std.debug.print("", .{ self, name });
    }

    pub fn data(self: *Builder, dType: []const u8, value: []const u8) !void {
        std.debug.print("data", .{ self, dType, value });
    }

    pub fn movq(self: *Builder, src: Operand, dst: Operand) !void {
        std.debug.print("movq", .{ self, src, dst });
    }

    pub fn cmpq(self: *Builder, src: Operand, dst: Operand) !void {
        std.debug.print("cmpq", .{ self, src, dst });
    }

    pub fn je(self: *Builder, l: []u8) !void {
        std.debug.print("je", .{ self, l });
    }

    pub fn jne(self: *Builder, l: []u8) !void {
        std.debug.print("jne", .{ self, l });
    }
};

pub const rax = Register{ .name = "rax", .size = .Q };
pub const rbx = Register{ .name = "rbx", .size = .Q };
pub const rcx = Register{ .name = "rcx", .size = .Q };
pub const rdx = Register{ .name = "rdx", .size = .Q };
pub const rsi = Register{ .name = "rsi", .size = .Q };
pub const rdi = Register{ .name = "rdi", .size = .Q };
pub const rbp = Register{ .name = "rbp", .size = .Q };
pub const rsp = Register{ .name = "rsp", .size = .Q };
pub const r8 = Register{ .name = "r8", .size = .Q };
pub const r9 = Register{ .name = "r9", .size = .Q };
pub const r10 = Register{ .name = "r10", .size = .Q };
pub const r11 = Register{ .name = "r11", .size = .Q };
pub const r12 = Register{ .name = "r12", .size = .Q };
pub const r13 = Register{ .name = "r13", .size = .Q };
pub const r14 = Register{ .name = "r14", .size = .Q };
pub const r15 = Register{ .name = "r15", .size = .Q };
