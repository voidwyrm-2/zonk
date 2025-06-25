const std = @import("std");
const Allocator = std.mem.Allocator;
const AutoHashMap = std.AutoHashMap;
const StringHashMap = std.StringHashMap;
const ArrayList = std.ArrayList;
const File = std.fs.File;

const builtin = @import("builtin");
const native_os = builtin.os.tag;
const is_wasm = native_os == .wasi or native_os == .emscripten;

const DynLib =
    if (is_wasm)
        struct {
            pub fn open(path: []const u8) !DynLib {
                _ = path;
                return .{};
            }
            pub fn lookup(self: *@This(), comptime T: type, name: [:0]const u8) ?T {
                _ = self;
                _ = name;
                return null;
            }
            pub fn close(self: *@This()) void {
                _ = self;
            }
        }
    else
        std.DynLib;

const lib_lexer = @import("lexer.zig");
const Lexer = lib_lexer.Lexer;
const Token = lib_lexer.Token;
const TokenType = lib_lexer.TokenType;

const String = @import("String.zig");

// C FFI function signature
// char func(char *mem, unsigned long size, unsigned long *ptr);

pub const FFIFunc = *const fn ([*c]c_char, c_ulong, *c_ulong) callconv(.C) c_char;

pub const InterpreterError = error{
    MismatchedLoop,
    UnmappedLoopPosition,
    UnsupportedOSForOperation,
    ModuleDoesNotExist,
    NoModuleLoaded,
    FunctionDoesNotExist,
    FFIFunctionSignal,
};

const ObjectManager = ArrayList(*anyopaque);

fn getPathBase(allocator: Allocator, str: []const u8) !String {
    var i: usize = str.len - 1;
    while (str[i] != std.fs.path.sep) {
        i -= 1;

        if (i == 0)
            break;
    }

    var base = try allocator.alloc(u8, str.len - i - 1);

    for (i + 1..str.len, 0..) |j, k| {
        base[k] = str[j];
    }

    return String.init(allocator, base);
}

const system_lib_ext = switch (native_os) {
    .windows => ".dll",
    .macos => ".dylib",
    .wasi, .emscripten => ".wasm",
    else => ".so",
};

fn appendSystemLibExt(allocator: Allocator, path: []const u8) !String {
    var new_str = try allocator.alloc(u8, path.len + system_lib_ext.len);

    for (path, 0..) |c, i| {
        new_str[i] = c;
    }

    for (system_lib_ext, path.len..new_str.len) |c, i| {
        new_str[i] = c;
    }

    return String.init(allocator, new_str);
}

pub const Interpreter = struct {
    allocator: Allocator,
    strings: ArrayList(String),
    modules: StringHashMap(DynLib),
    current_module: ?DynLib = null,
    stdout: File,
    stdin: File,
    mem: []u8,
    ptr: usize = 0,
    err_string: []const u8 = "",

    const max_byte: usize = std.math.maxInt(u8);

    pub fn init(allocator: Allocator, stdout: File, stdin: File, memorySize: usize) !Interpreter {
        const i: Interpreter = .{
            .allocator = allocator,
            .strings = ArrayList(String).init(allocator),
            .modules = StringHashMap(DynLib).init(allocator),
            .stdout = stdout,
            .stdin = stdin,
            .mem = try allocator.alloc(u8, memorySize),
        };

        @memset(i.mem, 0);

        return i;
    }

    pub fn deinit(self: *Interpreter) void {
        defer self.allocator.free(self.mem);
        defer self.modules.deinit();

        var iter = self.modules.iterator();

        while (iter.next()) |module| {
            module.value_ptr.close();
        }

        for (self.strings.items) |str| {
            var mut_str = str;
            mut_str.deinit();
        }

        if (self.err_string.len > 0)
            self.allocator.free(self.err_string);
    }

    fn err(self: *Interpreter, comptime fmt: []const u8, args: anytype) !void {
        self.err_string = try std.fmt.allocPrint(self.allocator, fmt, args);
    }

    fn errt(self: *Interpreter, token: Token, comptime fmt: []const u8, args: anytype) !void {
        self.err_string = try token.errf(self.allocator, fmt, args);
    }

    pub fn getByte(self: *Interpreter) u8 {
        return self.mem[self.ptr];
    }

    pub fn setByte(self: *Interpreter, byte: u8) void {
        self.mem[self.ptr] = byte;
    }

    pub fn left(self: *Interpreter, by: usize) void {
        self.ptr =
            if (by > self.ptr)
                self.mem.len - (by - self.ptr)
            else
                self.ptr - by;
    }

    pub fn right(self: *Interpreter, by: usize) void {
        self.ptr =
            if (self.ptr + by > self.mem.len - 1)
                (self.ptr + by) - self.mem.len
            else
                self.ptr + by;
    }

    pub fn inc(self: *Interpreter, amount: usize) void {
        var byte: usize = self.getByte();

        byte =
            if (byte + amount > Interpreter.max_byte)
                (byte + amount) - Interpreter.max_byte - 1
            else
                byte + amount;

        self.setByte(@intCast(byte));
    }

    pub fn dec(self: *Interpreter, amount: usize) void {
        var byte: usize = self.getByte();

        byte =
            if (amount > byte)
                Interpreter.max_byte - (amount - byte) + 1
            else
                byte - amount;

        self.setByte(@intCast(byte));
    }

    pub fn copy(self: *Interpreter) void {
        const begining = self.ptr;
        defer self.ptr = begining;

        const parent = self.getByte();
        self.right(1);
        self.setByte(parent);
    }

    pub fn insertString(self: *Interpreter, string: []const u8) void {
        const begining = self.ptr;
        defer self.ptr = begining;

        for (string) |b| {
            self.setByte(b);
            self.right(1);
        }
    }

    fn getLoops(self: *Interpreter, tokens: []Token) !AutoHashMap(usize, usize) {
        var map = AutoHashMap(usize, usize).init(self.allocator);
        var openStack = ArrayList(struct { pos: usize, t: Token }).init(self.allocator);
        defer openStack.deinit();

        for (tokens, 0..) |t, i| {
            if (t.kind == TokenType.loop_open) {
                try openStack.append(.{ .pos = i, .t = t });
            } else if (t.kind == TokenType.loop_close) {
                if (openStack.pop()) |entry| {
                    try map.put(i, entry.pos);
                    try map.put(entry.pos, i);
                } else {
                    try self.errt(t, "mismatched ']'", .{});
                    return InterpreterError.MismatchedLoop;
                }
            }
        }

        if (openStack.pop()) |entry| {
            try self.errt(entry.t, "mismatched '['", .{});
            return InterpreterError.MismatchedLoop;
        }

        return map;
    }

    fn wasi_unsupported_dynlib(self: *Interpreter, cur: Token) !void {
        if (is_wasm) {
            try self.errt(cur, "wasi/emscripten does not support dynamic loading", .{});
            return InterpreterError.UnsupportedOSForOperation;
        }
    }

    pub fn execute(self: *Interpreter, tokens: []Token) !void {
        const stdout_writer = self.stdout.writer();
        var outbw = std.io.bufferedWriter(stdout_writer);
        const stdout = outbw.writer();
        defer outbw.flush() catch {};

        const stdin_reader = self.stdin.reader();
        var inbr = std.io.bufferedReader(stdin_reader);
        const stdin = inbr.reader();

        var skip_stdin_newline = false;

        var idx: usize = 0;
        var loopMap = try self.getLoops(tokens);
        defer loopMap.deinit();

        while (idx < tokens.len) {
            const cur = tokens[idx];

            switch (cur.kind) {
                .left => {
                    self.left(cur.size);
                },
                .right => {
                    self.right(cur.size);
                },
                .inc => {
                    self.inc(cur.size);
                },
                .dec => {
                    self.dec(cur.size);
                },
                .loop_open => {
                    if (self.getByte() == 0)
                        idx = loopMap.get(idx) orelse {
                            try self.errt(cur, "unmapped loop position {d}", .{idx});
                            return InterpreterError.UnmappedLoopPosition;
                        };
                },
                .loop_close => {
                    if (self.getByte() != 0)
                        idx = loopMap.get(idx) orelse {
                            try self.errt(cur, "unmapped loop position {d}", .{idx});
                            return InterpreterError.UnmappedLoopPosition;
                        };
                },
                .putc => {
                    try stdout.print("{c}", .{self.getByte()});
                },
                .getc => {
                    if (skip_stdin_newline)
                        try stdin.skipBytes(1, .{});

                    self.setByte(try stdin.readByte());
                    skip_stdin_newline = true;
                },
                .copy => {
                    self.copy();
                },
                .jump_forward => {
                    self.right(self.getByte());
                },
                .jump_back => {
                    self.left(self.getByte());
                },
                .string => {
                    self.insertString(cur.lit.str);
                },
                .import => {
                    try self.wasi_unsupported_dynlib(cur);

                    var path = try appendSystemLibExt(self.allocator, cur.lit.str);
                    defer path.deinit();

                    const base = try getPathBase(self.allocator, cur.lit.str);
                    try self.strings.append(base);

                    const lib = DynLib.open(path.str) catch |dynerr| {
                        if (dynerr == error.FileNotFound) {
                            try self.errt(cur, "cannot find module at path {s}", .{path.str});
                        }

                        return dynerr;
                    };

                    try self.modules.put(base.str, lib);
                },
                .module_switch => {
                    try self.wasi_unsupported_dynlib(cur);

                    if (self.modules.get(cur.lit.str)) |module| {
                        self.current_module = module;
                    } else {
                        try self.errt(cur, "module '{s}' does not exist", .{cur.lit.str});
                        return InterpreterError.ModuleDoesNotExist;
                    }
                },
                .func_call => {
                    try self.wasi_unsupported_dynlib(cur);

                    if (self.current_module) |module| {
                        var mutable_module = module;

                        var modname = try self.allocator.alloc(u8, cur.lit.str.len + 1);
                        defer self.allocator.free(modname);

                        for (cur.lit.str, 0..) |c, i| {
                            modname[i] = c;
                        }

                        modname[cur.lit.str.len] = 0;

                        if (mutable_module.lookup(FFIFunc, @ptrCast(modname))) |extfunc| {
                            const cptr = try self.allocator.create(c_ulong);
                            defer self.allocator.destroy(cptr);

                            cptr.* = @intCast(self.ptr);

                            const res = extfunc(@ptrCast(self.mem.ptr), @intCast(self.mem.len), cptr);
                            if (res != 0) {
                                try self.errt(cur, "external function '{s}' signaled that an error occured with code {d}", .{ cur.lit.str, res });
                                return InterpreterError.FFIFunctionSignal;
                            }

                            self.ptr = cptr.*;
                        } else {
                            try self.errt(cur, "function '{s}' does not exist", .{cur.lit.str});
                            return InterpreterError.FunctionDoesNotExist;
                        }
                    } else {
                        try self.errt(cur, "no module loaded as the current module, use '$[name]' to load an imported module", .{});
                        return InterpreterError.NoModuleLoaded;
                    }
                },
            }

            idx += 1;
        }
    }
};
