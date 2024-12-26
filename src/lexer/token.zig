const std = @import("std");

pub const RawToken = struct {
    tag: Tag,
    loc: Loc,

    pub const Loc = struct {
        start: u32,
        end: u32,
    };

    pub const Tag = enum {
        invalid,
        eof,
        def,
        // ':'
        colon,
        identifier,
        add,
        sub,
        mul,
        // "//"
        div,
        // %
        percent,
        /// ==
        equal_equal,
        ne,
        /// <
        lt,
        /// <=
        le,
        /// >
        gt,
        /// >=
        ge,
        /// =
        equal,
        @"and",
        @"or",
        new_line,
        space,
        int,
        string,
        true,
        false,
        none,
        /// (
        l_paren,
        /// )
        r_paren,
        /// {
        l_brace,
        /// }
        r_brace,
        comma,
        /// [
        l_bracket,
        /// ]
        r_bracket,
        @"return",
        @"else",
        @"for",
        @"if",
        in,
        not,
        print,
    };

    pub const keywords = std.StaticStringMap(Tag).initComptime(.{ .{ "def", Tag.def }, .{ "True", Tag.true }, .{ "False", Tag.false }, .{ "none", Tag.none }, .{ "return", Tag.@"return" }, .{ "and", Tag.@"and" }, .{ "or", Tag.@"or" }, .{ "else", Tag.@"else" }, .{ "for", Tag.@"for" }, .{ "if", Tag.@"if" }, .{ "in", Tag.in }, .{ "not", Tag.not }, .{ "print", Tag.print }, .{ "None", Tag.none } });

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }
};
