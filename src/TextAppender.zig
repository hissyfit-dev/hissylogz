//! hissylogz - Text appender
//!
//! Appenders are expected to be re-used, e.g. support `reset()` being called, but *ONLY* at the _same_ log level.
//! Although this appender is not itself thread-safe, via `Logger`, appenders (like this one) will be managed in a thread-safe pool.

const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
const testing = std.testing;

const base64 = @import("base64.zig");

const constants = @import("constants.zig");
const limits = @import("limits.zig");
pub const errors = @import("errors.zig");
pub const AccessError = errors.AccessError;
pub const AllocationError = errors.AllocationError;
pub const LogBuffer = @import("LogBuffer.zig");
pub const LogLevel = constants.LogLevel;
pub const LogTime = @import("LogTime.zig");
pub const Ulid = @import("ulid.zig").Ulid;

/// Case to use for log level
pub const LogLevelNameCase = enum {
    upper,
    lower,
};
pub var log_level_name_case: LogLevelNameCase = .upper;

const Self = @This();

const std_logger = std.log.scoped(.hissylogz_text_appender);

pub const default_logging_level: LogLevel = .debug;

pub const Output = constants.LogOutput;

allocator: std.mem.Allocator,
output: Output,
output_mutex: *std.Thread.Mutex,
log_buffer: LogBuffer,
level: LogLevel,
log_time: LogTime,
tid: std.Thread.Id,
log_name: []const u8,

pub fn init(allocator: std.mem.Allocator, log_name: []const u8, output: Output, output_mutex: *std.Thread.Mutex, level: LogLevel, log_time: LogTime) AllocationError!Self {
    init_names_once.call();
    var new_log_buffer = try LogBuffer.init(allocator);
    errdefer new_log_buffer.deinit();

    return .{
        .allocator = allocator,
        .output = output,
        .output_mutex = output_mutex,
        .log_buffer = new_log_buffer,
        .level = level,
        .log_time = log_time,
        .log_name = log_name,
        .tid = std.Thread.getCurrentId(),
    };
}

pub fn deinit(self: *Self) void {
    self.log_buffer.deinit();
}

pub fn reset(self: *Self, log_time: LogTime) void {
    self.log_time = log_time;
    self.tid = std.Thread.getCurrentId();
    self.log_buffer.reset();
}

pub fn ctx(self: *Self, value: []const u8) void {
    var w = self.log_buffer.writer();
    w.print("<{s}> ", .{value}) catch return;
}

pub fn src(self: *Self, value: std.builtin.SourceLocation) void {
    var w = self.log_buffer.writer();
    w.print("@src=\"{s}:{d}: {s}\" ", .{ value.file, value.line, value.fn_name }) catch return;
}

pub fn msg(self: *Self, opt_value: ?[]const u8) void {
    const value = opt_value orelse {
        return;
    };
    var w = self.log_buffer.writer();
    w.print("{s}. ", .{value}) catch return;
}

pub fn name(self: *Self, opt_value: ?[]const u8) void {
    const value = opt_value orelse {
        return;
    };
    self.log_name = value;
}

pub fn str(self: *Self, key: []const u8, opt_value: ?[]const u8) void {
    const value = opt_value orelse {
        self.writeNull(key);
        return;
    };
    var w = self.log_buffer.writer();
    w.print("{s}=", .{key}) catch return;
    std.json.encodeJsonString(value, .{}, w) catch return;
    w.writeAll(" ") catch return;
}

pub fn strZ(self: *Self, key: []const u8, opt_value: ?[*:0]const u8) void {
    if (opt_value == null) {
        self.writeNull(key);
        return;
    }
    self.str(key, std.mem.span(opt_value));
}

pub fn ulid(self: *Self, key: []const u8, opt_value: ?Ulid) void {
    if (opt_value == null) {
        self.writeNull(key);
        return;
    }
    var w = self.log_buffer.writer();
    w.print("{s}=\"{any}\" ", .{ key, opt_value }) catch return;
}

pub fn int(self: *Self, key: []const u8, value: anytype) void {
    const int_val = switch (@typeInfo(@TypeOf(value))) {
        .Optional => blk: {
            if (value) |v| {
                break :blk v;
            }
            self.writeNull(key);
            return;
        },
        .Null => {
            self.writeNull(key);
            return;
        },
        else => value,
    };

    var w = self.log_buffer.writer();
    w.print("{s}={d} ", .{ key, int_val }) catch return;
}

pub fn intx(self: *Self, key: []const u8, value: anytype) void {
    const int_val = switch (@typeInfo(@TypeOf(value))) {
        .Optional => blk: {
            if (value) |v| {
                break :blk v;
            }
            self.writeNull(key);
            return;
        },
        .Null => {
            self.writeNull(key);
            return;
        },
        else => value,
    };

    var w = self.log_buffer.writer();
    w.print("{s}=0x{x} ", .{ key, int_val }) catch return;
}

pub fn intb(self: *Self, key: []const u8, value: anytype) void {
    const int_val = switch (@typeInfo(@TypeOf(value))) {
        .Optional => blk: {
            if (value) |v| {
                break :blk v;
            }
            self.writeNull(key);
            return;
        },
        .Null => {
            self.writeNull(key);
            return;
        },
        else => value,
    };

    var w = self.log_buffer.writer();
    w.print("{s}=0b{b} ", .{ key, int_val }) catch return;
}

pub fn float(self: *Self, key: []const u8, value: anytype) void {
    const float_val = switch (@typeInfo(@TypeOf(value))) {
        .Optional => blk: {
            if (value) |v| {
                break :blk v;
            }
            self.writeNull(key);
            return;
        },
        .Null => {
            self.writeNull(key);
            return;
        },
        else => value,
    };

    var w = self.log_buffer.writer();
    w.print("{s}={d} ", .{ key, float_val }) catch return;
}

pub fn boolean(self: *Self, key: []const u8, value: anytype) void {
    const bool_val = switch (@typeInfo(@TypeOf(value))) {
        .Optional => blk: {
            if (value) |v| {
                break :blk v;
            }
            self.writeNull(key);
            return;
        },
        .Null => {
            self.writeNull(key);
            return;
        },
        else => value,
    };

    var w = self.log_buffer.writer();
    w.print("{s}={s} ", .{ key, if (bool_val) "true" else "false" }) catch return;
}

pub fn obj(self: *Self, key: []const u8, value: anytype) void {
    const obj_val = switch (@typeInfo(@TypeOf(value))) {
        .Optional => blk: {
            if (value) |v| {
                break :blk v;
            }
            self.writeNull(key);
            return;
        },
        .Null => {
            self.writeNull(key);
            return;
        },
        else => value,
    };

    var w = self.log_buffer.writer();
    w.print("{s}=", .{key}) catch return;
    std.json.stringify(obj_val, .{}, w) catch {
        w.print("{self}", .{key}) catch return;
    };
    w.writeByte(' ') catch return;
}

pub fn any(self: *Self, key: []const u8, value: anytype) void {
    const any_val = switch (@typeInfo(@TypeOf(value))) {
        .Optional => blk: {
            if (value) |v| {
                break :blk v;
            }
            self.writeNull(key);
            return;
        },
        .Null => {
            self.writeNull(key);
            return;
        },
        else => value,
    };

    var w = self.log_buffer.writer();
    w.print("{s}={any} ", .{ key, any_val }) catch return;
}

pub fn binary(self: *Self, key: []const u8, opt_value: ?[]const u8) void {
    const value = opt_value orelse {
        self.writeNull(key);
        return;
    };

    const encoded = base64.encode(self.allocator, value) catch return;
    defer self.allocator.free(encoded);

    var w = self.log_buffer.writer();
    w.print("{s}=base64(\"{s}\") ", .{ key, encoded }) catch return;
}

pub fn err(self: *Self, value: anyerror) void {
    return self.errK("@err", value);
}

pub fn errK(self: *Self, key: []const u8, value: anyerror) void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .Optional => {
            if (value) |v| {
                self.rawStr(key, @errorName(v));
            } else {
                self.writeNull(key);
            }
        },
        else => self.rawStr(key, @errorName(value)),
    }
}

pub fn trace(self: *Self, opt_value: ?[]const u8) void {
    self.str("trace", opt_value);
}

pub fn span(self: *Self, opt_value: ?[]const u8) void {
    self.str("span", opt_value);
}

pub fn fmt(self: *Self, key: []const u8, comptime format: []const u8, values: anytype) void {
    var w = self.log_buffer.writer();
    w.print("{s}=", .{key}) catch return;
    std.fmt.format(w, format, values) catch return;
    w.writeByte(' ') catch return;
}

fn rawStr(self: *Self, key: []const u8, value: []const u8) void {
    var w = self.log_buffer.writer();
    w.print("{s}={s} ", .{ key, value }) catch return;
}

fn writeNull(self: *Self, key: []const u8) void {
    self.log_buffer.writer().print("{s}=null ", .{key}) catch return;
}

fn writeObject(self: *Self, key: []const u8, value: anytype) void {
    var w = self.log_buffer.writer();
    w.print("{s}=", .{key}) catch return;
    std.json.stringify(value, .{}, w) catch return;
    w.writeByte(' ') catch return;
}

pub fn tryLog(self: *Self) AccessError!void {
    try self.logTo(self.output.writer);
}

pub fn log(self: *Self) void {
    self.logTo(self.output.writer) catch |e| {
        std_logger.err("Failed to append log entry, entry dropped. Error was: {}", .{e});
    };
}

fn logTo(self: *Self, writer: anytype) AccessError!void {
    var out_buffer = self.log_buffer.contents();
    if (out_buffer.len == 0) {
        return;
    }

    // Lock output
    self.output_mutex.lock();
    defer self.output_mutex.unlock();

    // Write log entry
    const tid = std.Thread.getCurrentId();
    nosuspend writer.print("{rfc3339} {s: <5} [{s: <35} ({d:0>8})]: {s}\n", .{
        self.log_time,
        log_level_names[@intFromEnum(self.level)],
        self.log_name,
        tid,
        out_buffer[0 .. out_buffer.len - 1], // skip trailing space (' ')
    }) catch |e| {
        std.debug.print("Access error writing log entry: {any}\n", .{e});
        std_logger.err("Access error writing log entry: {any}\n", .{e});
        return AccessError.AccessFailure;
    };
}

// This once-per-lifetime function should be invoked using `init_names_once.call()`
var init_names_once = std.once(initLogLevelNames);
var log_level_names: [constants.num_log_levels][]const u8 = undefined;
var llnb: [constants.num_log_levels][7]u8 = undefined;
fn initLogLevelNames() void {
    const fn_convert: *const fn (output: []u8, ascii_string: []const u8) []u8 = switch (log_level_name_case) {
        .upper => std.ascii.upperString,
        .lower => std.ascii.lowerString,
    };

    for (0..constants.num_log_levels) |idx| {
        const tag_name = @tagName(@as(LogLevel, @enumFromInt(idx)));
        log_level_names[idx] = fn_convert(llnb[idx][0..tag_name.len], tag_name);
    }
}

const TextAppender = @This();

test "text appender - binary" {
    std.debug.print("text appender - binary\n", .{});
    const allocator = testing.allocator;

    const appender_output: TextAppender.Output = .{
        .writer = std.io.getStdErr().writer(),
    };
    var mtx: std.Thread.Mutex = .{};
    var text_appender = try TextAppender.init(
        allocator,
        "text",
        appender_output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer text_appender.deinit();

    const unencoded = [_]u8{ 'b', 'i', 'n', 'a', 'r', 'y' };
    const encoded = try base64.encode(allocator, &unencoded);
    defer allocator.free(encoded);
    text_appender.binary("key", &unencoded);
    try expectLogPostfixFmt(&text_appender, "key=base64(\"{s}\")", .{encoded});

    {
        text_appender.binary("key", @as(?[]const u8, null));
        try expectLogPostfix(&text_appender, "key=null");
    }

    const data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 };
    for (1..17) |i| {
        const real = try base64.encode(allocator, data[0..i]);
        defer allocator.free(real);
        text_appender.binary("k", data[0..i]);
        try expectLogPostfixFmt(&text_appender, "k=base64(\"{s}\")", .{real});
    }
}

test "text appender - int" {
    std.debug.print("text appender - int\n", .{});
    const allocator = testing.allocator;

    const appender_output: TextAppender.Output = .{
        .writer = std.io.getStdErr().writer(),
    };
    var mtx: std.Thread.Mutex = .{};
    var text_appender = try TextAppender.init(
        allocator,
        "text",
        appender_output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer text_appender.deinit();

    text_appender.int("key", 0);
    try expectLogPostfix(&text_appender, "key=0");

    text_appender.int("key", -1);
    try expectLogPostfix(&text_appender, "key=-1");

    text_appender.int("key", 1066);
    try expectLogPostfix(&text_appender, "key=1066");

    text_appender.int("key", -600);
    try expectLogPostfix(&text_appender, "key=-600");

    text_appender.int("n", @as(?u32, null));
    try expectLogPostfix(&text_appender, "n=null");
}

test "text appender - boolean" {
    std.debug.print("text appender - boolean\n", .{});
    const allocator = testing.allocator;

    const appender_output: TextAppender.Output = .{
        .writer = std.io.getStdErr().writer(),
    };
    var mtx: std.Thread.Mutex = .{};
    var text_appender = try TextAppender.init(
        allocator,
        "text",
        appender_output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer text_appender.deinit();

    text_appender.boolean("cats", true);
    try expectLogPostfix(&text_appender, "cats=true");

    text_appender.boolean("dogs", false);
    try expectLogPostfix(&text_appender, "dogs=false");

    text_appender.boolean("rats", @as(?bool, null));
    try expectLogPostfix(&text_appender, "rats=null");
}

test "text appender - float" {
    std.debug.print("text appender - float\n", .{});
    const allocator = testing.allocator;

    const appender_output: TextAppender.Output = .{
        .writer = std.io.getStdErr().writer(),
    };
    var mtx: std.Thread.Mutex = .{};
    var text_appender = try TextAppender.init(
        allocator,
        "text",
        appender_output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer text_appender.deinit();

    text_appender.float("key", 0);
    try expectLogPostfix(&text_appender, "key=0");

    text_appender.float("key", -1);
    try expectLogPostfix(&text_appender, "key=-1");

    text_appender.float("key", 12345.67891);
    try expectLogPostfix(&text_appender, "key=12345.67891");

    text_appender.float("key", -1.234567891);
    try expectLogPostfix(&text_appender, "key=-1.234567891");

    text_appender.float("key", @as(?f64, null));
    try expectLogPostfix(&text_appender, "key=null");
}

test "text appender - error" {
    std.debug.print("text appender - error\n", .{});
    const allocator = testing.allocator;

    const appender_output: TextAppender.Output = .{
        .writer = std.io.getStdErr().writer(),
    };
    var mtx: std.Thread.Mutex = .{};
    var text_appender = try TextAppender.init(
        allocator,
        "text",
        appender_output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer text_appender.deinit();

    text_appender.errK("errK", error.OutOfMemory);
    try expectLogPostfix(&text_appender, "errK=OutOfMemory");

    text_appender.err(error.OutOfMemory);
    try expectLogPostfix(&text_appender, "@err=OutOfMemory");
}

test "text appender - ctx" {
    std.debug.print("text appender - ctx\n", .{});
    const allocator = testing.allocator;

    const appender_output: TextAppender.Output = .{
        .writer = std.io.getStdErr().writer(),
    };
    var mtx: std.Thread.Mutex = .{};
    var text_appender = try TextAppender.init(
        allocator,
        "text",
        appender_output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer text_appender.deinit();

    text_appender.ctx("some context");
    try expectLogPostfix(&text_appender, "<some context>");
}

test "text appender - src" {
    std.debug.print("text appender - src\n", .{});
    const allocator = testing.allocator;

    const appender_output: TextAppender.Output = .{
        .writer = std.io.getStdErr().writer(),
    };
    var mtx: std.Thread.Mutex = .{};
    var text_appender = try TextAppender.init(
        allocator,
        "text",
        appender_output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer text_appender.deinit();

    const local_src = @src();
    text_appender.src(local_src);
    try expectLogPostfixFmt(&text_appender, "@src=\"src/TextAppender.zig:{d}: test.text appender - src\"", .{local_src.line});
}

test "text appender - any" {
    std.debug.print("text appender - any\n", .{});
    const allocator = testing.allocator;

    const appender_output: TextAppender.Output = .{
        .writer = std.io.getStdErr().writer(),
    };
    var mtx: std.Thread.Mutex = .{};
    var json_appender = try TextAppender.init(
        allocator,
        "text",
        appender_output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer json_appender.deinit();

    const rats = .{ .some = "some", .thing = "thing" };

    json_appender.any("rats", rats);
    try expectLogPostfixFmt(&json_appender, "rats=struct{{comptime some: *const [4:0]u8 = \"some\", comptime thing: *const [5:0]u8 = \"thing\"}}{{ .some = {{ 115, 111, 109, 101 }}, .thing = {{ 116, 104, 105, 110, 103 }} }}", .{});
}

fn expectLogPostfix(text_appender: *TextAppender, comptime expected: ?[]const u8) !void {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    try out.ensureTotalCapacity(100);
    defer out.deinit();

    try text_appender.logTo(out.writer());
    if (expected) |e| {
        try std.testing.expectEqualStrings(e, extractPostfix(out.items));
    } else {
        try std.testing.expectEqual(0, out.items.len);
    }
    text_appender.reset(LogTime.now());
}

fn expectLogPostfixFmt(text_appender: *TextAppender, comptime format: []const u8, args: anytype) !void {
    defer text_appender.reset(LogTime.now());

    var out = std.ArrayList(u8).init(std.testing.allocator);
    try out.ensureTotalCapacity(100);
    defer out.deinit();

    try text_appender.logTo(out.writer());

    var buf: [200]u8 = undefined;
    const expected = try std.fmt.bufPrint(&buf, format, args);
    try std.testing.expectEqualStrings(expected, extractPostfix(out.items));
    text_appender.reset(LogTime.now());
}

fn extractPostfix(text: []const u8) []const u8 {
    const ts_len = 42;
    const level_len = @tagName(default_logging_level).len;
    const tid_len = 8;
    const name_len = 20 + 3;
    const prefix_len = ts_len + 1 + level_len + 2 + tid_len + name_len + 2 + 1;
    if (text.len <= prefix_len) {
        return text;
    }
    return text[prefix_len .. text.len - 1]; // Exclude final newline
}

// ---
// hissylogz.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
