//! hissylogz - Logging buffer

const std = @import("std");
const testing = std.testing;

const base64 = @import("base64.zig");

pub const errors = @import("errors.zig");
pub const AllocationError = errors.AllocationError;

const Self = @This();
const LogBuffer = @This();

const initial_logging_buffer_size = @import("limits.zig").default_initial_logging_buffer_size;

const BufferArray = std.ArrayList(u8);

allocator: std.mem.Allocator,
buffer_array: BufferArray,

pub fn init(allocator: std.mem.Allocator) AllocationError!Self {
    var new_buffer_array = BufferArray.initCapacity(allocator, initial_logging_buffer_size) catch return AllocationError.OutOfMemory;
    errdefer new_buffer_array.deinit();
    return .{
        .allocator = allocator,
        .buffer_array = new_buffer_array,
    };
}

pub fn deinit(self: *Self) void {
    self.buffer_array.deinit();
}

pub inline fn reset(self: *Self) void {
    self.buffer_array.clearRetainingCapacity();
}

pub fn write(ctx: *Self, data: []const u8) AllocationError!usize {
    ctx.buffer_array.writer().writeAll(data) catch return AllocationError.OutOfMemory;
    return data.len;
}

pub inline fn print(self: *Self, comptime format: []const u8, args: anytype) !void {
    return self.buffer_array.writer().print(format, args);
}

pub inline fn contents(self: Self) []const u8 {
    return self.buffer_array.items;
}

pub const Writer = std.io.GenericWriter(*Self, AllocationError, write);

pub inline fn writer(self: *Self) Writer {
    return .{ .context = self };
}

test "log buffer - smoke test" {
    std.debug.print("log buffer - smoke test\n", .{});
    const allocator = testing.allocator;

    var log_buffer = try LogBuffer.init(allocator);
    defer log_buffer.deinit();

    std.debug.print("\tlog buffer writer\n", .{});
    try log_buffer.writer().writeAll("And this");
    try log_buffer.writer().writeAll(" should work");
    try testing.expectEqualStrings("And this should work", log_buffer.contents());

    std.debug.print("\tlog buffer direct write\n", .{});
    log_buffer.reset();
    _ = try log_buffer.write("ABCXYZ");
    try testing.expectEqualStrings("ABCXYZ", log_buffer.contents());

    std.debug.print("\tlog buffer print\n", .{});
    log_buffer.reset();
    try log_buffer.print("This {d} and that {d}", .{ 4, 2 });
    try testing.expectEqualStrings("This 4 and that 2", log_buffer.contents());
    log_buffer.reset();
    try log_buffer.print("{d}2{d}4", .{ 1, 3 });
    try testing.expectEqualStrings("1234", log_buffer.contents());
}

test "log buffer - embedded" {
    std.debug.print("log buffer - embedded\n", .{});
    const allocator = testing.allocator;

    const SomeHolder = struct {
        inner_log_buffer: LogBuffer,
        message: []const u8,

        pub fn writeSome(self: *@This()) !void {
            try self.inner_log_buffer.writer().print("Some message: {s}", .{self.message});
        }
    };

    var log_buffer = try LogBuffer.init(allocator);
    defer log_buffer.deinit();

    var some: SomeHolder = .{ .inner_log_buffer = log_buffer, .message = "Sanity, please?" };

    try some.writeSome();
    try testing.expectEqualStrings("Some message: Sanity, please?", some.inner_log_buffer.buffer_array.items);

    some.inner_log_buffer.reset();
    try some.inner_log_buffer.print("{d}2{d}4", .{ 1, 3 });
    try testing.expectEqualStrings("1234", some.inner_log_buffer.buffer_array.items);
}

// ---
// hissylogz.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
