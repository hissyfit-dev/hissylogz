//! Making a song and dance about hissylogz.

const std = @import("std");
const debug = std.debug;
const io = std.io;

const hissylogz = @import("hissylogz.zig");
const LoggerPool = hissylogz.LoggerPool;

const errors = hissylogz.errors;

pub fn main() !void {
    std.debug.print("hissylogz - song and dance\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);

    try hissylogz.initGlobalLoggerPool(allocator, .{
        .writer = &stdout_writer.interface,
        .filter_level = .info,
        .log_format = .text,
    });
    defer hissylogz.deinitGlobalLoggerPool();

    var logger = hissylogz.globalLoggerPool().logger("hissylogz");

    const no_op_time = try timeNoopLogging(hissylogz.globalLoggerPool());
    logger.info()
        .msg("no-op logging")
        .int("times", 10_000)
        .int("nanoseconds", no_op_time)
        .log();

    var thread_logger_pool = try hissylogz.loggerPool(allocator, .{
        .filter_level = .fine,
        .log_format = .text,
        .writer = &stdout_writer.interface,
    });
    defer thread_logger_pool.deinit();

    var threads: [10]std.Thread = undefined;

    for (0..9) |tno| {
        threads[tno] = try std.Thread.spawn(.{}, threadLogger, .{ &thread_logger_pool, allocator, tno });
    }

    for (0..9) |tno| {
        std.Thread.join(threads[tno]);
    }
}

fn threadLogger(logger_pool: *hissylogz.LoggerPool, allocator: std.mem.Allocator, tno: usize) void {
    const logger_name = std.fmt.allocPrint(allocator, "tno-{d}", .{tno}) catch return;
    defer allocator.free(logger_name);

    var logger = logger_pool.logger(logger_name);

    for (0..5) |idx| {
        logger.fine()
            .msg("Fine entry")
            .src(@src())
            .intb("idx", idx)
            .log();
        logger.debug()
            .msg("Debug entry")
            .src(@src())
            .intx("idx", idx)
            .log();
        logger.info()
            .msg("Info entry")
            .int("idx", idx)
            .log();
        logger.warn()
            .msg("Warning entry")
            .int("idx", idx)
            .log();
        logger.err()
            .msg("Error entry")
            .src(@src())
            .int("idx", idx)
            .log();
        logger.fatal()
            .msg("Fatal error entry")
            .log();
    }
}

fn timeNoopLogging(pool: *LoggerPool) !u64 {
    var logger = pool.logger("no-op");
    var t = try std.time.Timer.start();
    const started = t.read();
    for (0..10_000) |idx| {
        logger.debug().int("idx", idx).log();
    }
    return t.read() - started;
}

// ---
// hissylogz.
//
// Copyright 2024,2025 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
