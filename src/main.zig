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

    try hissylogz.initGlobalLoggerPool(allocator, .{
        .writer = @constCast(&std.io.getStdOut().writer()),
        .filter_level = .info,
    });
    defer hissylogz.deinitGlobalLoggerPool();

    useGlobalLoggerPool();

    const no_op_time = try timeNoopLogging(hissylogz.globalLoggerPool());
    std.debug.print("no-op logging 10,000 times: {d}ns ({d}μs) ({d}ms)\n", .{
        no_op_time,
        @as(i64, @intCast(@divFloor(no_op_time, std.time.ns_per_us))),
        @as(i64, @intCast(@divFloor(no_op_time, std.time.ns_per_ms))),
    });

    var threads: [10]std.Thread = undefined;

    for (0..9) |tno| {
        threads[tno] = try std.Thread.spawn(.{}, threadLogger, .{ allocator, tno });
    }

    for (0..9) |tno| {
        std.Thread.join(threads[tno]);
    }

    const one_two_three = try allocator.dupe(u8, "one two three");
    allocator.free(one_two_three);
}

fn threadLogger(allocator: std.mem.Allocator, tno: usize) void {
    const logger_name = std.fmt.allocPrint(allocator, "tno-{d}", .{tno}) catch return;
    defer allocator.free(logger_name);

    const tid = std.Thread.getCurrentId();

    var logger = hissylogz.globalLoggerPool().logger(logger_name);

    for (0..5) |idx| {
        logger.fine().msg("Fine entry").int("tid", tid).src(@src()).int("idx", idx).log();
        logger.debug().msg("Debug entry").int("tid", tid).src(@src()).int("idx", idx).log();
        logger.info().msg("Info entry").int("tid", tid).src(@src()).int("idx", idx).log();
        logger.warn().msg("Warning entry").int("tid", tid).src(@src()).int("idx", idx).log();
        logger.err().msg("Error entry").int("tid", tid).src(@src()).int("idx", idx).log();
        logger.fatal().msg("Fatal error entry").int("tid", tid).src(@src()).int("idx", idx).log();
    }
}

fn useGlobalLoggerPool() void {
    var logger = hissylogz.globalLoggerPool().logger("useGlobalLoggerPool");
    logger.fine().msg("Fine entry").src(@src()).str("first", "Hidden entry").int("entry#", 1).boolean("appears", false).log();
    logger.debug().msg("Debug entry").src(@src()).str("second", "Hidden entry").int("entry#", 2).boolean("appears", false).log();
    logger.info().msg("Informational entry").src(@src()).str("third", "Visible entry").int("entry#", 3).boolean("appears", true).log();
    logger.warn().msg("Warning entry").src(@src()).str("fourth", "Another visible entry").int("entry#", 4).boolean("appears", true).log();
    logger.err().msg("Error entry").src(@src()).str("fifth", "Yet another visible entry").int("entry#", 5).boolean("appears", true).log();
    logger.fatal().msg("Fatal error entry").src(@src()).str("sixth", "Yet another visible entry").int("entry#", 6).boolean("appears", true).log();
}

fn timeNoopLogging(pool: *LoggerPool) !u64 {
    var t = try std.time.Timer.start();
    const started = t.read();
    var logger = pool.logger("no-op");
    for (0..10_000) |idx| {
        logger.debug().int("idx", idx).log();
    }
    return t.read() - started;
}

// ---
// hissylogz.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
