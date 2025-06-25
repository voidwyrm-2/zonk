const std = @import("std");
const Allocator = std.mem.Allocator;

const Self = @This();

allocator: ?Allocator = null,
str: []const u8 = "",

/// Returns a new String with an underlying slice and a contained allocator.
/// Use `unmanaged` for a String without an allocator.
pub fn init(allocator: Allocator, str: []const u8) Self {
    return .{
        .allocator = allocator,
        .str = str,
    };
}

/// Returns a new String with an underlying slice, but no contained allocator.
/// Use `init` for a String with an allocator.
pub fn unmanaged(str: []const u8) Self {
    return .{
        .str = str,
    };
}

/// Frees the underlying slice using the contained allocator if it has one.
pub fn deinit(self: *Self) void {
    if (self.allocator) |allocator| {
        allocator.free(self.str);
    }
}
