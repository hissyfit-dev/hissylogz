//! hissylogz - Structured logging support for Zig.

const std = @import("std");
const testing = std.testing;

const constants = @import("constants.zig");
pub const ulid = @import("ulid.zig");
const Ulid = ulid.Ulid;

pub const errors = @import("errors.zig");

pub const LogLevel = constants.LogLevel;
pub const LogFormat = constants.LogFormat;
pub const LogOutput = constants.LogOutput;
pub const LogOptions = constants.LogOptions;
pub const LogTime = @import("LogTime.zig");

pub const Logger = @import("Logger.zig");
pub const LoggerPool = @import("LoggerPool.zig");

const JsonAppender = @import("JsonAppender.zig");
const TextAppender = @import("TextAppender.zig");

const std_logger = std.log.scoped(.hissylogz);

var global_log_filter_level: LogLevel = .info;
var global_pool_mutex: std.Thread.Mutex = .{};
var global_pool: ?LoggerPool = null;

pub const Options = struct {
    filter_level: LogLevel = .info,
    log_format: LogFormat = .json,
    writer: *std.fs.File.Writer,
    ns_ts_supplier: *const fn () i128 = std.time.nanoTimestamp,
};

pub fn loggerPool(allocator: std.mem.Allocator, options: Options) errors.AllocationError!LoggerPool {
    const output: constants.LogOutput = .{
        .writer = options.writer,
    };
    const log_options: LogOptions = .{
        .output = output,
        .format = options.log_format,
        .level = options.filter_level,
        .ns_ts_supplier = options.ns_ts_supplier,
    };
    return try LoggerPool.init(allocator, log_options);
}

pub fn initGlobalLoggerPool(allocator: std.mem.Allocator, options: Options) errors.AllocationError!void {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();
    if (global_pool) |_| {
        return;
    }
    global_pool = try loggerPool(allocator, options);
}

pub fn deinitGlobalLoggerPool() void {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();
    if (global_pool) |*current_global| {
        current_global.deinit();
    }
}

pub fn globalLoggerPool() *LoggerPool {
    global_pool_mutex.lock();
    defer global_pool_mutex.unlock();
    if (global_pool) |*current_global_pool| {
        return current_global_pool;
    }
    @panic("Please initialize hissylogz global logger pool first.");
}

test "hissylogz - loggerPool()" {
    std.debug.print("hissylogz - loggerPool()\n", .{});

    const allocator = testing.allocator;

    std.debug.print("\tlogger pool\n", .{});
    var logger_pool = try loggerPool(allocator, .{
        .writer = @constCast(&std.io.getStdErr().writer()),
        .filter_level = .info,
    });

    var l = logger_pool.logger("hissylogz - loggerPool()");
    l.info().ctx("local").str("test", "appears").log();
    l.debug().ctx("local").str("test", "does not appear").log();

    defer logger_pool.deinit();
}

test "hissylogz - globalLoggerPool()" {
    std.debug.print("hissylogz - globalLoggerPool()\n", .{});

    const allocator = testing.allocator;

    std.debug.print("\tinit global logger pool\n", .{});
    try initGlobalLoggerPool(allocator, .{
        .writer = @constCast(&std.io.getStdErr().writer()),
        .filter_level = .debug,
    });
    defer deinitGlobalLoggerPool();

    std.debug.print("\tuse global logger pool\n", .{});

    var l = globalLoggerPool().logger("hissylogz - globalLoggerPool()");
    l.info().ctx("global").str("test", "appears").log();
    l.debug().ctx("global").str("test", "also appears").log();
}

test "hissylogz - dependencies trigger" {
    std.debug.print("hissylogz - dependencies trigger\n", .{});

    const allocator = testing.allocator;

    std.debug.print("\tjson appender\n", .{});

    var w = std.io.getStdErr().writer();
    _ = &w;
    var mtx: std.Thread.Mutex = .{};
    const output: LogOutput = .{
        .writer = &w,
    };
    var json_appender = try JsonAppender.init(
        allocator,
        "json",
        output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer json_appender.deinit();

    std.debug.print("\ttext appender\n", .{});

    var text_appender = try JsonAppender.init(
        allocator,
        "text",
        output,
        &mtx,
        .debug,
        LogTime.now(),
    );
    defer text_appender.deinit();

    std.debug.print("\tlogger\n", .{});
    const log_options: LogOptions = .{
        .format = .json,
        .level = .debug,
        .output = output,
        .ns_ts_supplier = std.time.nanoTimestamp,
    };

    var logger = try Logger.init("logging", allocator, log_options, &mtx);
    defer logger.deinit();

    std.debug.print("\tlogger pool\n", .{});
    var logger_pool = try LoggerPool.init(allocator, log_options);
    defer logger_pool.deinit();
}

// ---
// hissylogz.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
