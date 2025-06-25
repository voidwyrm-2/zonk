const std = @import("std");

const lib_lexer = @import("lexer.zig");
const Token = lib_lexer.Token;

pub const CZonkToken = extern struct {
    kind: c_int,
    lit: [*c]const u8,

    pub fn fromToken(token: Token) CZonkToken {
        return .{
            .kind = @intFromEnum(token.kind),
            .lit = token.lit.ptr,
        };
    }
};
