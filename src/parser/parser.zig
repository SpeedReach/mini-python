const std = @import("std");
const lex = @import("../lexer/lexer.zig");

pub const Parser = struct {
    lexer: lex.Lexer,

    pub fn init(allocator: std.mem.Allocator, buffer: [:0]const u8) Parser {
        const lexer = lex.Lexer.init(allocator, buffer);
        return .{ .lexer = lexer };
    }
};
