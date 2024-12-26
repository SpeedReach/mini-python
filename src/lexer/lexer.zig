const token = @import("./token.zig");
const tokenizer = @import("./tokenizer.zig");
const std = @import("std");
const ds = @import("../mini_python.zig").ds;

pub const TokenTag = enum {
    new_line,
    begin,
    end,
    raw,
};

pub const Token = union(TokenTag) {
    new_line,
    begin,
    end,
    raw: token.RawToken,
};

/// A line of code is: newline, indent, expr
pub const State = enum {
    new_line,
    expr,
};

pub const Lexer = struct {
    allocator: std.mem.Allocator,
    tokenizer: tokenizer.Tokenizer,
    indent_stack: std.ArrayList(u32),
    state: State = .new_line,
    /// when we have more than one tokens to return, we store them here
    queue: ds.Queue(Token),

    pub fn init(allocator: std.mem.Allocator, buffer: [:0]const u8) Lexer {
        return .{
            .allocator = allocator,
            .queue = ds.Queue(Token).init(allocator),
            .tokenizer = tokenizer.Tokenizer.init(buffer),
            .indent_stack = std.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.indent_stack.deinit();
        self.queue.deinit();
    }

    pub const LexingError = error{
        IndentError,
        InvalidToken,
    };

    pub fn peek(self: *Lexer) !Token {
        if (self.queue.len() > 0) {
            return self.queue.peek().?;
        }
        const tok = try self.next();
        try self.queue.enqueue(tok);
        return tok;
    }

    pub fn pos(self: *Lexer) u32 {
        return self.tokenizer.index;
    }

    pub fn next(self: *Lexer) !Token {
        if (self.queue.len() > 0) {
            const node = self.queue.dequeue();
            return node.?;
        }
        while (true) {
            switch (self.state) {
                .new_line => {
                    const tok = self.tokenizer.next();
                    if (tok.tag == token.RawToken.Tag.new_line) {
                        continue;
                    }
                    self.state = .expr;
                    const prev_indent = self.indent_stack.getLastOrNull() orelse 0;

                    const is_expr = tok.tag != token.RawToken.Tag.space;
                    const current_indent = if (tok.tag == token.RawToken.Tag.space) tok.loc.end - tok.loc.start else 0;
                    switch (tok.tag) {
                        token.RawToken.Tag.space => {
                            if (current_indent == prev_indent) {
                                continue;
                            } else if (current_indent > prev_indent) {
                                try self.indent_stack.append(current_indent);
                                return Token.begin;
                            }
                        },
                        else => {
                            if (prev_indent == 0) {
                                return Token{ .raw = tok };
                            }
                        },
                    }

                    // if we reach here , it means prev_indent > indent
                    // we'll pop the indent_stack until we find the matching indent
                    // for each pop, we'll add an end token

                    while (true) {
                        const last_indent = self.indent_stack.getLastOrNull() orelse 0;
                        //std.debug.print("last_indent: {}, current_indent: {}\n", .{ last_indent, current_indent });
                        if (last_indent == 0) {
                            break;
                        }
                        if (current_indent >= last_indent) {
                            break;
                        }
                        _ = self.indent_stack.popOrNull();
                        try self.queue.enqueue(Token.end);
                    }

                    if (is_expr) {
                        try self.queue.enqueue(Token{ .raw = tok });
                    }
                    return self.queue.dequeue() orelse LexingError.IndentError;
                },
                .expr => {
                    const tok = self.tokenizer.next();
                    switch (tok.tag) {
                        .space => {
                            continue;
                        },
                        .new_line => {
                            self.state = .new_line;
                            return Token.new_line;
                        },
                        .invalid => {
                            return LexingError.InvalidToken;
                        },
                        else => {
                            return Token{ .raw = tok };
                        },
                    }
                },
            }
        }
    }
};

const test_allocator = std.testing.allocator;
const ArrayList = std.ArrayList;

test "test lexer" {
    const buffer =
        \\def add(a, b)  
        \\  a[b] = c
        \\  if(c == 123)
        \\    print("hello\n")
        \\      aaa
        \\        bbb
        \\      ccc
        \\return a+b "aaa "
    ;
    var lexer = Lexer.init(test_allocator, buffer);
    var tokens = ArrayList(Token).init(test_allocator);
    defer tokens.deinit();
    defer lexer.deinit();

    while (true) {
        const tok = try lexer.next();
        try tokens.append(tok);
        switch (tok) {
            .raw => {
                switch (tok.raw.tag) {
                    .eof => {
                        break;
                    },
                    else => {},
                }
            },
            else => {},
        }
        switch (tok) {
            .raw => {
                std.debug.print("{s}\n", .{buffer[tok.raw.loc.start..tok.raw.loc.end]});
            },
            else => {
                std.debug.print("{}\n", .{tok});
            },
        }
    }
}
