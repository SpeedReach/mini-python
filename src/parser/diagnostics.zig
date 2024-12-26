pub const symbol = @import("./symbol.zig");

pub const ErrorTag = enum {
    ExpectTerminal,
    ExpectNonTerminal,
};

pub const Error = union(ErrorTag) {
    ExpectedTerminal: struct {
        got: ?symbol.Terminals,
        expect: symbol.Terminals,
        start: usize,
        end: usize,
    },
    ExpectedNonTerminal: struct {
        expect: symbol.NoneTerminals,
        start: usize,
        end: usize,
    },
};

pub const Message = struct { err: Error };
