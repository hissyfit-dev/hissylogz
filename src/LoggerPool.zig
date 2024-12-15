//! hissylogz - Logger Pool

const std = @import("std");
const testing = std.testing;

const constants = @import("constants.zig");

pub const errors = @import("errors.zig");
pub const AccessError = errors.AccessError;
pub const AllocationError = errors.AllocationError;

pub const Level = constants.LogLevel.Level;
pub const LogOptions = constants.LogOptions;
pub const Logger = @import("Logger.zig");

const std_logger = std.log.scoped(.hissylogz_logger_pool);

const Self = @This();
const LoggerMap = std.StringArrayHashMap(*Logger);

allocator: std.mem.Allocator,
options: LogOptions,
loggers: LoggerMap,
output_mutex: *std.Thread.Mutex,
rw_lock: std.Thread.RwLock,
noop_logger: Logger,

pub fn init(allocator: std.mem.Allocator, options: LogOptions) AllocationError!Self {
    const noop_ts_supplier = struct {
        fn supply() i128 {
            return 0;
        }
    };
    const noop_options: LogOptions = .{
        .format = options.format,
        .level = .none,
        .output = options.output,
        .ns_ts_supplier = noop_ts_supplier.supply,
    };
    const output_mutex = allocator.create(std.Thread.Mutex) catch return AllocationError.OutOfMemory;
    errdefer allocator.destroy(output_mutex);
    output_mutex.* = .{};

    const noop_logger = try Logger.init("no-op", allocator, noop_options, output_mutex);
    errdefer noop_logger.deinit();

    return .{
        .allocator = allocator,
        .options = options,
        .loggers = LoggerMap.init(allocator),
        .output_mutex = output_mutex,
        .rw_lock = .{},
        .noop_logger = noop_logger,
    };
}

pub fn deinit(self: *Self) void {
    defer self.allocator.destroy(self.output_mutex);
    defer self.loggers.deinit();
    defer self.noop_logger.deinit();
    self.rw_lock.lock();
    defer self.rw_lock.unlock();
    var it = self.loggers.iterator();
    while (it.next()) |entry| {
        entry.value_ptr.*.deinit();
        self.allocator.destroy(entry.value_ptr.*);
    }
}

pub fn logger(self: *Self, name: []const u8) *Logger {
    self.rw_lock.lockShared();
    errdefer self.rw_lock.unlockShared();

    if (self.fetchExisting(name)) |existing_logger| {
        defer self.rw_lock.unlockShared();
        return existing_logger;
    }
    self.rw_lock.unlockShared();

    self.rw_lock.lock();
    defer self.rw_lock.unlock();

    return self.fetchOrAdd(name) catch |e| {
        std_logger.warn("Using fallback logger due to error: {any}", .{e});
        return &self.noop_logger;
    };
}

fn fetchOrAdd(self: *Self, name: []const u8) AllocationError!*Logger {
    const gpr = self.loggers.getOrPut(name) catch |e| {
        std_logger.err("Failed to acquire logger [{s}]: {any}", .{ name, e });
        return AllocationError.OutOfMemory;
    };

    if (!gpr.found_existing) {
        // Create new logger
        var new_logger = self.allocator.create(Logger) catch |e| {
            std_logger.err("Failed to acquire logger [{s}]: {any}", .{ name, e });
            return AllocationError.OutOfMemory;
        };
        errdefer self.allocator.destroy(new_logger);
        new_logger.* = try Logger.init(name, self.allocator, self.options, self.output_mutex);
        errdefer new_logger.deinit();
        gpr.value_ptr.* = new_logger;
    }

    return gpr.value_ptr.*;
}

fn fetchExisting(self: *Self, name: []const u8) ?*Logger {
    var existing = self.loggers.get(name);
    _ = &existing;

    return existing;
}

const LogOutput = constants.LogOutput;
const LogLevel = constants.LogLevel;

const LoggerPool = @This();

test "logger pool - smoke test" {
    std.debug.print("logger pool - smoke test\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const output: LogOutput = .{
        .writer = &werr,
    };
    const log_options: LogOptions = .{
        .format = .json,
        .level = .debug,
        .output = output,
        .ns_ts_supplier = std.time.nanoTimestamp,
    };

    var logger_pool = try LoggerPool.init(allocator, log_options);
    defer logger_pool.deinit();

    logger_pool.noop_logger.info().str("oblivion", "This should go to oblivion").log();

    var logger_1 = logger_pool.logger("logger_1");
    try testing.expectEqual(logger_1, logger_pool.logger("logger_1"));

    logger_1.debug().ctx("debug smoke test").log();
    logger_1.info().ctx("info smoke test").log();

    var entry_1 = logger_1.info().ctx("info entry 1");
    var entry_2 = logger_1.info().ctx("info entry 2");

    entry_1.log();
    entry_2.log();

    var logger_2 = logger_pool.logger("logger_2");
    try testing.expectEqual(logger_2, logger_pool.logger("logger_2"));

    logger_2.info().src(@src()).int("one", 1).log();
    logger_2.info().src(@src()).str("useful", "perhaps").log();
    logger_2.warn().str("dire", "warning").log();
}

// ---
// hissylogz.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
