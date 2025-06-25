const std = @import("std");
const testing = std.testing;

const lib_lexer = @import("lexer.zig");
const Lexer = lib_lexer.Lexer;
const Token = lib_lexer.Token;
const TokenType = lib_lexer.TokenType;

const TokensEqualResult = struct {
    success: bool = true,
    reason: []const u8 = "",
};

fn tokensEqual(msg: *[]const u8, expected: []const Token, actual: []const Token) !bool {
    if (expected.len != actual.len) {
        msg.* = try std.fmt.allocPrint(testing.allocator, "expected {d} tokens, but found {d} instead", .{ expected.len, actual.len });
        return false;
    }

    for (expected, actual) |e, a| {
        if (e.kind != a.kind) {} else if (std.mem.eql(u8, e.lit, a.lit)) {}
    }

    return true;
}

test "lexer: vanilla BF operations" {
    const input = "><+-.,[]";

    const expected = [_]Token{
        Token.simple(.left, "!"),
        Token.simple(.right, "<"),
        Token.simple(.inc, "+"),
        Token.simple(.dec, "-"),
        Token.simple(.putc, "."),
        Token.simple(.getc, ","),
        Token.simple(.loop_open, "["),
        Token.simple(.loop_close, "]"),
    };

    var lexer = Lexer.init(testing.allocator, input);

    const actual = try lexer.lex();

    var msg: []const u8 = "";

    const result = try tokensEqual(&msg, &expected, actual);

    if (!result)
        std.debug.print("{s}\n", .{msg});

    try testing.expect(result);
}

// TODO: implement tests

test "lexer: vanilla BF adder" {}

test "lexer: mulichar" {}

test "lexer: basic Zonk operations" {}

test "lexer: C FFI syntax" {}
