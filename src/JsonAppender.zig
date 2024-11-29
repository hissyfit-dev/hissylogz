//! hissylogz - JSON appender
//!
//! Appenders are expected to be re-used, e.g. support `reset()` being called, but *ONLY* at the _same_ log level.
//! Although this appender is not itself thread-safe, via `Logger`, appenders (like this one) will be managed in a thread-safe pool.

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const base64 = @import("base64.zig");

const constants = @import("constants.zig");
const limits = @import("limits.zig");
pub const errors = @import("errors.zig");
pub const AccessError = errors.AccessError;
pub const AllocationError = errors.AllocationError;
pub const LogBuffer = @import("LogBuffer.zig");
pub const Timestamp = constants.Timestamp;
pub const LogLevel = constants.LogLevel;
pub const Ulid = @import("hissybitz").ulid.Ulid;

const Self = @This();

const std_logger = std.log.scoped(.hissylogz_json_appender);

pub const default_logging_level: LogLevel = .debug;

pub const Output = constants.LogOutput;

allocator: std.mem.Allocator,
output: Output,
output_mutex: *std.Thread.Mutex,
log_buffer: LogBuffer,
level: LogLevel,
timestamp: Timestamp,

pub fn init(allocator: std.mem.Allocator, output: Output, output_mutex: *std.Thread.Mutex, level: LogLevel, timestamp: Timestamp) AllocationError!Self {
    var new_log_buffer = try LogBuffer.init(allocator);
    errdefer new_log_buffer.deinit();

    return .{
        .allocator = allocator,
        .output = output,
        .output_mutex = output_mutex,
        .log_buffer = new_log_buffer,
        .level = level,
        .timestamp = timestamp,
    };
}

pub fn deinit(self: *Self) void {
    self.log_buffer.deinit();
}

pub fn reset(self: *Self) void {
    self.timestamp = Timestamp.now();
    self.log_buffer.reset();
}

pub fn ctx(self: *Self, value: []const u8) void {
    self.str("@ctx", value);
}

pub fn src(self: *Self, value: std.builtin.SourceLocation) void {
    var w = self.log_buffer.writer();
    w.writeAll("\"@src\":") catch return;
    std.json.stringify(.{ .file = value.file, .@"fn" = value.fn_name, .line = value.line }, .{}, w) catch return;
    w.writeByte(',') catch return;
}

pub fn str(self: *Self, key: []const u8, opt_value: ?[]const u8) void {
    const value = opt_value orelse {
        self.writeNull(key);
        return;
    };
    var w = self.log_buffer.writer();
    w.print("\"{s}\":", .{key}) catch return;
    std.json.encodeJsonString(value, .{}, w) catch return;
    w.writeByte(',') catch return;
}

pub fn msg(self: *Self, opt_value: ?[]const u8) void {
    self.str("@msg", opt_value);
}

pub fn name(self: *Self, opt_value: ?[]const u8) void {
    self.str("@log", opt_value);
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
    w.print("\"{s}\":\"{any}\",", .{ key, opt_value }) catch return;
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
    w.print("\"{s}\":{d},", .{ key, int_val }) catch return;
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
    w.print("\"{s}\":0x{x},", .{ key, int_val }) catch return;
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
    w.print("\"{s}\":{d},", .{ key, float_val }) catch return;
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
    w.print("\"{s}\":{s},", .{ key, if (bool_val) "true" else "false" }) catch return;
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
    w.print("\"{s}\":", .{key}) catch return;
    std.json.stringify(obj_val, .{}, w) catch {
        w.print("{self}", .{key}) catch return;
    };
    w.writeByte(',') catch return;
}

pub fn binary(self: *Self, key: []const u8, opt_value: ?[]const u8) void {
    const value = opt_value orelse {
        self.writeNull(key);
        return;
    };

    const encoded = base64.encode(self.allocator, value) catch return;
    defer self.allocator.free(encoded);

    var w = self.log_buffer.writer();
    w.print("\"{s}\":\"{s}\",", .{ key, encoded }) catch return;
}

pub fn err(self: *Self, value: anyerror) void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .Optional => {
            if (value) |v| {
                self.str("@err", @errorName(v));
            } else {
                self.writeNull("@err");
            }
        },
        else => self.str("@err", @errorName(value)),
    }
}

pub fn errK(self: *Self, key: []const u8, value: anyerror) void {
    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .Optional => {
            if (value) |v| {
                self.str(key, @errorName(v));
            } else {
                self.writeNull(key);
            }
        },
        else => self.str(key, @errorName(value)),
    }
}

pub fn trace(self: *Self, opt_value: ?[]const u8) void {
    self.str("@trace_id", opt_value);
}

pub fn span(self: *Self, opt_value: ?[]const u8) void {
    self.str("@span_id", opt_value);
}

pub fn fmt(self: *Self, key: []const u8, comptime format: []const u8, values: anytype) void {
    var w = self.log_buffer.writer();
    w.print("\"{s}\":\"", .{key}) catch return;
    std.fmt.format(w, format, values) catch return;
    w.writeAll("\",") catch return;
}

pub fn tryLog(self: *Self) AccessError!void {
    try self.logTo(self.output.writer);
}

fn writeNull(self: *Self, key: []const u8) void {
    self.log_buffer.writer().print("\"{s}\":null,", .{key}) catch return;
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
    nosuspend writer.print("{{\"@ts\":\"{rfc3339}\",\"@lvl\":\"{s}\",{s}}}\n", .{
        self.timestamp,
        @tagName(self.level),
        out_buffer[0 .. out_buffer.len - 1],
    }) catch |e| {
        std.debug.print("Access error writing log entry: {any}\n", .{e});
        std_logger.err("Access error writing log entry: {any}\n", .{e});
        return AccessError.AccessFailure;
    };
}

const JsonAppender = @This();

test "json appender - smoke test" {
    std.debug.print("json appender - smoke test\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_appender_extra1 = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender_extra1.deinit();
    _ = try json_appender_extra1.log_buffer.write("ABCXYZ");

    var json_appender_extra2 = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender_extra2.deinit();
    json_appender_extra2.str("embedded_string_key", "embedded_string");
    json_appender_extra2.int("embedded_int_key", 1234);

    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();
    json_appender.msg("Checking various values");
    json_appender.trace("12345-1234");
    json_appender.str("string_key", "string");
    json_appender.str("null_string_key", null);
    json_appender.int("int_key", 1066);
    json_appender.int("null_int_key", null);
    const embedded = try allocator.dupe(u8, json_appender_extra2.log_buffer.contents());
    defer allocator.free(embedded);
    embedded[embedded.len - 1] = '}';
    json_appender.str("embedded_key", embedded);

    try werr.writeByte('\t');
    json_appender.log();

    const expected = "\"@msg\":\"Checking various values\",\"@trace_id\":\"12345-1234\",\"string_key\":\"string\",\"null_string_key\":null,\"int_key\":1066,\"null_int_key\":null,\"embedded_key\":\"\\\"embedded_string_key\\\":\\\"embedded_string\\\",\\\"embedded_int_key\\\":1234}\"}";
    try expectLogPostfix(&json_appender, expected);
}

test "json appender - binary" {
    std.debug.print("json appender - binary\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();

    const unencoded = [_]u8{ 'b', 'i', 'n', 'a', 'r', 'y' };
    const encoded = try base64.encode(allocator, &unencoded);
    defer allocator.free(encoded);
    json_appender.binary("key", &unencoded);
    try expectLogPostfixFmt(&json_appender, "\"key\":\"{s}\"}}", .{encoded});

    {
        json_appender.binary("key", @as(?[]const u8, null));
        try expectLogPostfix(&json_appender, "\"key\":null}");
    }

    const data = [_]u8{ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 };
    for (1..17) |i| {
        const real = try base64.encode(allocator, data[0..i]);
        defer allocator.free(real);
        json_appender.binary("k", data[0..i]);
        try expectLogPostfixFmt(&json_appender, "\"k\":\"{s}\"}}", .{real});
    }
}

test "json appender - int" {
    std.debug.print("json appender - int\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();

    json_appender.int("key", 0);
    try expectLogPostfix(&json_appender, "\"key\":0}");

    json_appender.int("key", -1);
    try expectLogPostfix(&json_appender, "\"key\":-1}");

    json_appender.int("key", 1066);
    try expectLogPostfix(&json_appender, "\"key\":1066}");

    json_appender.int("key", -600);
    try expectLogPostfix(&json_appender, "\"key\":-600}");

    json_appender.int("n", @as(?u32, null));
    try expectLogPostfix(&json_appender, "\"n\":null}");
}

test "json appender - intx" {
    std.debug.print("json appender - intx\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();

    json_appender.intx("key", 0);
    try expectLogPostfix(&json_appender, "\"key\":0x0}");

    json_appender.intx("key", 1066);
    try expectLogPostfix(&json_appender, "\"key\":0x42a}");

    json_appender.intx("n", @as(?u32, null));
    try expectLogPostfix(&json_appender, "\"n\":null}");
}

test "json appender - boolean" {
    std.debug.print("json appender - boolean\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();

    json_appender.boolean("cats", true);
    try expectLogPostfix(&json_appender, "\"cats\":true}");

    json_appender.boolean("dogs", false);
    try expectLogPostfix(&json_appender, "\"dogs\":false}");

    json_appender.boolean("rats", @as(?bool, null));
    try expectLogPostfix(&json_appender, "\"rats\":null}");
}

test "json appender - float" {
    std.debug.print("json appender - float\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();

    json_appender.float("key", 0);
    try expectLogPostfix(&json_appender, "\"key\":0}");

    json_appender.float("key", -1);
    try expectLogPostfix(&json_appender, "\"key\":-1}");

    json_appender.float("key", 12345.67891);
    try expectLogPostfix(&json_appender, "\"key\":12345.67891}");

    json_appender.float("key", -1.234567891);
    try expectLogPostfix(&json_appender, "\"key\":-1.234567891}");

    json_appender.float("key", @as(?f64, null));
    try expectLogPostfix(&json_appender, "\"key\":null}");
}

test "json appender - error" {
    std.debug.print("json appender - error\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();

    json_appender.errK("errK", error.OutOfMemory);
    try expectLogPostfix(&json_appender, "\"errK\":\"OutOfMemory\"}");

    json_appender.err(error.OutOfMemory);
    try expectLogPostfix(&json_appender, "\"@err\":\"OutOfMemory\"}");
}

test "json appender - ctx" {
    std.debug.print("json appender - ctx\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();

    json_appender.ctx("some context");
    try expectLogPostfix(&json_appender, "\"@ctx\":\"some context\"}");
}

test "json appender - src" {
    std.debug.print("json appender - src\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();

    const local_src = @src();
    json_appender.src(local_src);
    try expectLogPostfixFmt(&json_appender, "\"@src\":{{\"file\":\"src/JsonAppender.zig\",\"fn\":\"test.json appender - src\",\"line\":{d}}}}}", .{local_src.line});
}

test "json appender - obj" {
    std.debug.print("json appender - obj\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const appender_output: JsonAppender.Output = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};
    var json_appender = try JsonAppender.init(allocator, appender_output, &mtx, .debug, constants.Timestamp.now());
    defer json_appender.deinit();

    const rats = .{ .some = "some", .thing = "thing" };

    json_appender.obj("rats", rats);
    try expectLogPostfixFmt(&json_appender, "\"rats\":{{\"some\":\"some\",\"thing\":\"thing\"}}}}", .{});
}

fn expectLogPostfix(json_appender: *JsonAppender, comptime expected: ?[]const u8) !void {
    var out = std.ArrayList(u8).init(std.testing.allocator);
    try out.ensureTotalCapacity(100);
    defer out.deinit();

    try json_appender.logTo(out.writer());
    if (expected) |e| {
        try std.testing.expectEqualStrings(e, extractPostfix(out.items));
    } else {
        try std.testing.expectEqual(0, out.items.len);
    }
    json_appender.reset();
}

fn expectLogPostfixFmt(json_appender: *JsonAppender, comptime format: []const u8, args: anytype) !void {
    defer json_appender.reset();

    var out = std.ArrayList(u8).init(std.testing.allocator);
    try out.ensureTotalCapacity(100);
    defer out.deinit();

    try json_appender.logTo(out.writer());

    var buf: [200]u8 = undefined;
    const expected = try std.fmt.bufPrint(&buf, format, args);
    try std.testing.expectEqualStrings(expected, extractPostfix(out.items));
    json_appender.reset();
}

fn extractPostfix(text: []const u8) []const u8 {
    const ts_len = 30;
    const level_len = @tagName(default_logging_level).len;
    const prefix_len = 1 + (4 + 3 + ts_len + 1) + 1 + (4 + 4 + level_len + 1) + 1;
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
