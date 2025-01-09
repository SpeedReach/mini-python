const token = @import("./token.zig");
const std = @import("std");

const State = enum {
    start,
    eof,
    identifier,
    invalid,
    number,
    @"or",
    @"and",
    not,
    greater,
    lesser,
    equal,
    bang,
    div,
    angle_bracket_left,
    angle_bracket_right,
    space,
    string_literal,
    string_literal_backslash,
    comment,
};

pub const Tokenizer = struct {
    buffer: [:0]const u8,
    index: u32,

    pub fn init(buffer: [:0]const u8) Tokenizer {
        return .{ .buffer = buffer, .index = 0 };
    }

    pub fn next(self: *Tokenizer) token.RawToken {
        var result = token.RawToken{
            .tag = .invalid,
            .loc = token.RawToken.Loc{ .start = self.index, .end = undefined },
        };

        var state = State.start;
        while (true) {
            switch (state) {
                .start => {
                    switch (self.buffer[self.index]) {
                        0 => {
                            if (self.index == self.buffer.len) {
                                return .{ .tag = .eof, .loc = .{ .end = self.index, .start = self.index } };
                            } else {
                                state = .invalid;
                                continue;
                            }
                        },
                        '0'...'9' => {
                            state = .number;
                            continue;
                        },
                        'a'...'z', 'A'...'Z' => {
                            state = .identifier;
                            continue;
                        },
                        '[' => {
                            self.index += 1;
                            result.tag = .l_bracket;
                            break;
                        },
                        ']' => {
                            self.index += 1;
                            result.tag = .r_bracket;
                            break;
                        },
                        '(' => {
                            self.index += 1;
                            result.tag = .l_paren;
                            break;
                        },
                        ')' => {
                            self.index += 1;
                            result.tag = .r_paren;
                            break;
                        },
                        '{' => {
                            self.index += 1;
                            result.tag = .l_brace;
                            break;
                        },
                        '}' => {
                            self.index += 1;
                            result.tag = .r_brace;
                            break;
                        },
                        ',' => {
                            self.index += 1;
                            result.tag = .comma;
                            break;
                        },
                        '%' => {
                            self.index += 1;
                            result.tag = .percent;
                            break;
                        },
                        '+' => {
                            self.index += 1;
                            result.tag = .add;
                            break;
                        },
                        '-' => {
                            self.index += 1;
                            result.tag = .sub;
                            break;
                        },
                        ':' => {
                            self.index += 1;
                            result.tag = .colon;
                            break;
                        },
                        '*' => {
                            self.index += 1;
                            result.tag = .mul;
                            break;
                        },
                        '/' => {
                            state = .div;
                            continue;
                        },
                        '>' => {
                            state = .angle_bracket_left;
                            continue;
                        },
                        '<' => {
                            state = .angle_bracket_right;
                            continue;
                        },
                        '!' => {
                            state = .bang;
                            continue;
                        },
                        '=' => {
                            state = .equal;
                            continue;
                        },
                        '\n', '\r' => {
                            self.index += 1;
                            result.tag = .new_line;
                            break;
                        },
                        ' ' => {
                            state = .space;
                            continue;
                        },
                        '"' => {
                            state = .string_literal;
                            continue;
                        },
                        '#' => {
                            state = .comment;
                            result.tag = .comment;
                            continue;
                        },
                        else => {
                            state = .invalid;
                            continue;
                        },
                    }
                },
                .comment => {
                    self.index += 1;
                    if (self.index >= self.buffer.len) {
                        state = .invalid;
                        break;
                    }
                    switch (self.buffer[self.index]) {
                        0 => {
                            state = .invalid;
                            continue;
                        },
                        '\n', '\r' => {
                            result.tag = .new_line;
                            break;
                        },
                        else => {
                            continue;
                        },
                    }
                },
                .string_literal => {
                    self.index += 1;
                    if (self.index >= self.buffer.len) {
                        state = .invalid;
                        break;
                    }
                    switch (self.buffer[self.index]) {
                        0 => {
                            state = .invalid;
                            continue;
                        },
                        '"' => {
                            self.index += 1;
                            result.tag = .string;
                            break;
                        },
                        '\\' => {
                            state = .string_literal_backslash;
                            continue;
                        },
                        '\n', '\r' => {
                            state = .invalid;
                            continue;
                        },
                        else => {
                            continue;
                        },
                    }
                },
                .string_literal_backslash => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        0 => {
                            state = .invalid;
                            continue;
                        },
                        else => {
                            state = .string_literal;
                            continue;
                        },
                    }
                },
                .space => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        ' ' => {
                            continue;
                        },
                        '\n', '\r' => {
                            result.tag = .new_line;
                            break;
                        },
                        else => {
                            result.tag = .space;
                            break;
                        },
                    }
                },
                .equal => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        '=' => {
                            self.index += 1;
                            result.tag = .equal_equal;
                        },
                        else => {
                            result.tag = .equal;
                        },
                    }
                    break;
                },
                .bang => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        '=' => {
                            self.index += 1;
                            result.tag = .ne;
                            break;
                        },
                        else => {
                            state = .invalid;
                            continue;
                        },
                    }
                },
                .angle_bracket_left => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        '=' => {
                            self.index += 1;
                            result.tag = .ge;
                        },
                        else => {
                            result.tag = .gt;
                        },
                    }
                    break;
                },
                .angle_bracket_right => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        '=' => {
                            self.index += 1;
                            result.tag = .le;
                        },
                        else => {
                            result.tag = .lt;
                        },
                    }
                    break;
                },
                .div => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        '/' => {
                            self.index += 1;
                            result.tag = .div;
                            break;
                        },
                        else => {
                            state = .invalid;
                            break;
                        },
                    }
                },
                .identifier => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        'a'...'z', 'A'...'Z', '0'...'9', '_' => {
                            continue;
                        },
                        else => {
                            const keyword = token.RawToken.getKeyword(self.buffer[result.loc.start..self.index]);
                            if (keyword != null) {
                                result.tag = keyword.?;
                            } else {
                                result.tag = .identifier;
                            }
                            break;
                        },
                    }
                },
                .number => {
                    self.index += 1;
                    switch (self.buffer[self.index]) {
                        '0'...'9' => {
                            continue;
                        },
                        else => {
                            result.tag = .int;
                            break;
                        },
                    }
                },
                .invalid => {
                    self.index += 1;
                    if (self.index >= self.buffer.len) {
                        result.tag = .invalid;
                        break;
                    }
                    switch (self.buffer[self.index]) {
                        0 => {
                            if (self.index == self.buffer.len) {
                                return .{ .tag = .eof, .loc = .{ .end = self.index, .start = self.index } };
                            } else {
                                state = .invalid;
                                continue;
                            }
                        },
                        '\n', '\r' => {
                            self.index += 1;
                            result.tag = .invalid;
                            break;
                        },
                        else => {
                            continue;
                        },
                    }
                },
                else => {
                    state = .invalid;
                    continue;
                },
            }
        }

        result.loc.end = self.index;
        return result;
    }
};

const testing = std.testing;
const ArrayList = std.ArrayList;
const test_allocator = std.testing.allocator;

test "tokenize (abb+bdd)//c" {
    const buffer = "(abb+bdd)//c";
    var tokenizer = Tokenizer.init(buffer);

    const l_paren = tokenizer.next();
    const a = tokenizer.next();
    const add = tokenizer.next();
    const b = tokenizer.next();
    const r_paren = tokenizer.next();
    const mul = tokenizer.next();
    const c = tokenizer.next();
    const eof = tokenizer.next();

    try testing.expectEqual(token.RawToken.Tag.l_paren, l_paren.tag);
    try testing.expectEqual(token.RawToken.Tag.identifier, a.tag);
    try testing.expectEqualStrings("abb", buffer[a.loc.start..a.loc.end]);
    try testing.expectEqual(token.RawToken.Tag.add, add.tag);
    try testing.expectEqual(token.RawToken.Tag.identifier, b.tag);
    try testing.expectEqualStrings("bdd", buffer[b.loc.start..b.loc.end]);
    try testing.expectEqual(token.RawToken.Tag.r_paren, r_paren.tag);
    try testing.expectEqual(token.RawToken.Tag.div, mul.tag);
    try testing.expectEqual(token.RawToken.Tag.identifier, c.tag);
    try testing.expectEqualStrings("c", buffer[c.loc.start..c.loc.end]);
    try testing.expectEqual(token.RawToken.Tag.eof, eof.tag);
}

test "can lex" {
    const buffer =
        \\def add(a, b)
        \\  a[b] = c
        \\  if(c == 123) {
        \\    return 0
        \\  }
        \\  return a + b
    ;
    var lexer = Tokenizer.init(buffer);
    var tokens = ArrayList(token.RawToken).init(test_allocator);
    defer tokens.deinit();

    while (true) {
        const tok = lexer.next();
        try tokens.append(tok);
        if (tok.tag == .eof) {
            break;
        }
    }
    for (tokens.items) |item| {
        std.log.debug("Value: '{s}' {} \n", .{ buffer[item.loc.start..item.loc.end], item });
    }
}
