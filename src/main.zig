const std = @import("std");
const io = std.io;

const clap = @import("clap");

const lib_lexer = @import("lexer.zig");
const Lexer = lib_lexer.Lexer;
const Token = lib_lexer.Token;
const LexerError = lib_lexer.LexerError;

const lib_interpreter = @import("interpreter.zig");
const Interpreter = lib_interpreter.Interpreter;
const InterpreterError = lib_interpreter.InterpreterError;

const zonk_version = @import("version.zig").zonk_version; // dynamically generated via build.zig

const default_zonk_cells: usize = 30000;

pub fn main() !u8 {
    const allocator = std.heap.page_allocator;

    const stdout_writer = io.getStdOut().writer();
    var outbw = io.bufferedWriter(stdout_writer);
    const stdout = outbw.writer();

    defer outbw.flush() catch {};

    const stderr_writer = io.getStdErr().writer();
    var errbw = io.bufferedWriter(stderr_writer);
    const stderr = errbw.writer();

    defer errbw.flush() catch {};

    const params = comptime clap.parseParamsComptime(
        \\-h, --help           Display this help and exit.
        \\-v, --version        Print the current Zonk version.
        \\-t, --tokens         Print the tokens generated by the lexer.
        \\-m, --mem            Print the program memory after execution.
        \\-M, --mod            Print the loaded modules.
        \\-c, --cells <usize>  The amount of cells that the program has access to; defaults to 30000.
        \\<str>
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        diag.report(std.io.getStdErr().writer(), err) catch {};
        return 1;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.help(stdout_writer, clap.Help, &params, .{});
        return 0;
    }

    if (res.args.version != 0) {
        try stdout.print("Zonk interpreter version {s}\n", .{zonk_version});
        return 0;
    }

    if (res.positionals[0] == null) {
        try stderr.print("no input file\n", .{});
        return 1;
    }

    const input = res.positionals[0].?;

    const dir = std.fs.cwd();

    const maxSize = std.math.maxInt(usize);
    const data = dir.readFileAlloc(allocator, input, maxSize) catch |err| switch (err) {
        std.posix.OpenError.FileNotFound => {
            try stderr.print("file '{s}' does not exist\n", .{input});
            return 1;
        },
        else => return err,
    };
    defer allocator.free(data);

    var lexer = Lexer.init(allocator, data);
    defer lexer.deinit();

    const tokens = lexer.lex() catch |err| {
        if (lexer.err_string.len > 0) {
            try stderr.print("{s}\n", .{lexer.err_string});
            return 1;
        }

        return err;
    };

    var interpreter = try Interpreter.init(allocator, std.io.getStdOut(), std.io.getStdIn(), res.args.cells orelse default_zonk_cells);
    defer interpreter.deinit();

    interpreter.execute(tokens) catch |err| {
        if (interpreter.err_string.len > 0) {
            try stderr.print("{s}\n", .{interpreter.err_string});
            return 1;
        }

        return err;
    };

    if (res.args.tokens != 0) {
        for (tokens) |t| {
            try stdout.print("{s}\n", .{try t.str(allocator)});
        }
    }

    if (res.args.mem != 0) {
        try stdout.print("{any}\n", .{interpreter.mem});
    }

    if (res.args.mod != 0) {
        var iter = interpreter.modules.iterator();

        try stdout.print("loaded modules:\n", .{});

        while (iter.next()) |m| {
            try stdout.print(" '{s}'\n", .{m.key_ptr.*});
        }
    }

    return 0;
}
