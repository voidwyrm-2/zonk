const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const String = @import("String.zig");

pub const LexerError = error{
    IllegalCharacter,
    InvalidEscapeCharacter,
};

pub const TokenType = enum {
    left,
    right,
    inc,
    dec,
    loop_open,
    loop_close,
    putc,
    getc,
    copy,
    jump_forward,
    jump_back,
    string,
    import,
    module_switch,
    func_call,

    pub fn fromChar(ch: u8) ?TokenType {
        return switch (ch) {
            '<' => .left,
            '>' => .right,
            '+' => .inc,
            '-' => .dec,
            '[' => .loop_open,
            ']' => .loop_close,
            '.' => .putc,
            ',' => .getc,
            '_' => .copy,
            '/' => .jump_forward,
            '\\' => .jump_back,
            else => null,
        };
    }
};

pub const Token = struct {
    kind: TokenType,
    lit: String,
    col: usize,
    ln: usize,
    size: usize,

    pub fn init(
        kind: TokenType,
        lit: String,
        col: usize,
        ln: usize,
        size: usize,
    ) Token {
        return .{
            .kind = kind,
            .lit = lit,
            .col = col,
            .ln = ln,
            .size = size,
        };
    }

    pub fn simple(kind: TokenType, lit: String) Token {
        return Token.init(kind, lit, 0, 0, 0);
    }

    pub fn errf(self: Token, allocator: Allocator, comptime fmt: []const u8, args: anytype) std.fmt.AllocPrintError![]const u8 {
        const msg = try std.fmt.allocPrint(allocator, fmt, args);
        defer allocator.free(msg);
        return try std.fmt.allocPrint(allocator, "Error on line {d}, col {d}: {s}", .{ self.ln, self.col, msg });
    }

    pub fn str(self: Token, allocator: Allocator) ![]const u8 {
        return try std.fmt.allocPrint(allocator, "<{any}, `{s}`({d}), {d}, {d}>", .{ self.kind, self.lit.str, self.size, self.col, self.ln });
    }
};

pub const Lexer = struct {
    allocator: Allocator,
    init_objects: ArrayList(*anyopaque),
    text: []const u8,
    err_string: []const u8 = "",
    ch: ?u8,
    idx: usize = 0,
    col: usize = 1,
    ln: usize = 1,

    const string_delimiter = '"';
    const import_start = '{';
    const import_end = '}';
    const module_switch_delimiter = '$';
    const func_call_delimiter = '@';

    fn isIdent(ch: u8) bool {
        return (ch >= 'a' and 'z' >= ch) or (ch >= 'A' and 'Z' >= ch) or (ch >= '9' and '0' >= ch) or ch == '_';
    }

    pub fn init(allocator: Allocator, text: []const u8) Lexer {
        return .{
            .allocator = allocator,
            .init_objects = ArrayList(*anyopaque).init(allocator),
            .text = text,
            .ch = if (text.len > 0) text[0] else null,
        };
    }

    pub fn deinit(self: *Lexer) void {
        defer self.init_objects.deinit();

        for (self.init_objects.items) |obj| {
            const real: *struct {
                pub fn deinit(_self: *@This()) void {
                    _ = _self;
                }
            } = @ptrCast(obj);

            real.deinit();
        }

        if (self.err_string.len > 0)
            self.allocator.free(self.err_string);
    }

    fn createString(self: *Lexer, str: []const u8) String {
        return String.init(self.allocator, str);
    }

    fn errf(self: *Lexer, comptime str: []const u8, args: anytype) !void {
        const token = Token.init(.dec, .{}, self.col, self.ln, 0);
        self.err_string = try token.errf(self.allocator, str, args);
    }

    fn advance(self: *Lexer) void {
        self.idx += 1;
        self.col += 1;

        self.ch = if (self.idx < self.text.len) self.text[self.idx] else null;

        if (self.ch) |ch| {
            if (ch == '\n') {
                self.ln += 1;
                self.col = 0;
            }
        }
    }

    fn skipComment(self: *Lexer) void {
        while (self.ch != null and self.ch != '\n') {
            self.advance();
        }
    }

    fn collectChar(self: *Lexer, ch: u8, kind: TokenType) !Token {
        const start = self.col;
        const startln = self.ln;
        var size: usize = 0;

        while (self.ch) |subch| {
            if (subch != ch)
                break;

            size += 1;
            self.advance();
        }

        const str = try std.fmt.allocPrint(self.allocator, "{c}", .{ch});
        return Token.init(kind, self.createString(str), start, startln, size);
    }

    fn collectString(self: *Lexer) !Token {
        const start = self.col;
        const startln = self.ln;
        var lit = ArrayList(u8).init(self.allocator);
        try self.init_objects.append(@ptrCast(&lit));

        var escaped = false;

        self.advance();

        while (self.ch) |ch| {
            if (escaped) {
                const char = switch (ch) {
                    '\\', '\'', '"' => ch,
                    'n' => '\n',
                    't' => '\t',
                    'a' => 7,
                    '0' => 0,
                    else => {
                        return LexerError.InvalidEscapeCharacter;
                    },
                };

                try lit.append(char);
                escaped = false;
            } else if (ch == '\\') {
                escaped = true;
            } else if (ch == Lexer.string_delimiter) {
                break;
            } else {
                try lit.append(ch);
            }
            self.advance();
        }

        if (self.ch != Lexer.string_delimiter) {
            const token = Token.init(.dec, .{}, start, startln, 0);
            self.err_string = try token.errf(self.allocator, "unterminated string literal", .{});
        }

        self.advance();

        return Token.init(.string, String.unmanaged(lit.items), start, startln, lit.items.len + 2);
    }

    fn collectImport(self: *Lexer) !Token {
        const start = self.col;
        const startln = self.ln;
        var lit = ArrayList(u8).init(self.allocator);
        try self.init_objects.append(@ptrCast(&lit));

        self.advance();

        while (self.ch) |ch| {
            if (ch == Lexer.import_end)
                break;

            try lit.append(ch);

            self.advance();
        }

        if (self.ch != Lexer.import_end) {
            const token = Token.init(.dec, .{}, start, startln, 0);
            self.err_string = try token.errf(self.allocator, "unterminated import", .{});
        }

        self.advance();

        return Token.init(.import, String.unmanaged(lit.items), start, startln, lit.items.len + 2);
    }

    fn collectPrefixedIdent(self: *Lexer, kind: TokenType) !Token {
        const start = self.col;
        const startln = self.ln;
        var lit = ArrayList(u8).init(self.allocator);
        try self.init_objects.append(@ptrCast(&lit));

        self.advance();

        while (self.ch) |ch| {
            if (!Lexer.isIdent(ch))
                break;

            try lit.append(ch);

            self.advance();
        }

        return Token.init(kind, String.unmanaged(lit.items), start, startln, lit.items.len + 1);
    }

    pub fn lex(self: *Lexer) ![]Token {
        var tokens = try self.allocator.create(ArrayList(Token));
        tokens.* = ArrayList(Token).init(self.allocator);
        try self.init_objects.append(tokens);

        while (self.ch) |ch| {
            switch (ch) {
                ' ', '\t', '\n' => self.advance(),
                ';' => self.skipComment(),
                Lexer.string_delimiter => try tokens.append(try self.collectString()),
                Lexer.import_start => try tokens.append(try self.collectImport()),
                Lexer.module_switch_delimiter => try tokens.append(try self.collectPrefixedIdent(.module_switch)),
                Lexer.func_call_delimiter => try tokens.append(try self.collectPrefixedIdent(.func_call)),
                else => if (TokenType.fromChar(ch)) |kind| {
                    try tokens.append(try self.collectChar(ch, kind));
                } else {
                    try self.errf("illegal character '{c}'", .{ch});
                    return LexerError.IllegalCharacter;
                },
            }
        }

        return tokens.items;
    }
};
