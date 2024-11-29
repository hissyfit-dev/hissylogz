//! hissylogz - Logger.

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;

const constants = @import("constants.zig");

const base64 = @import("base64.zig");

const limits = @import("limits.zig");

pub const errors = @import("errors.zig");
pub const AccessError = errors.AccessError;
pub const AllocationError = errors.AllocationError;

pub const LogLevel = constants.LogLevel;
pub const LogOutput = constants.LogOutput;
pub const LogFormat = constants.LogFormat;
pub const LogOptions = constants.LogOptions;
pub const Timestamp = constants.Timestamp;
pub const Ulid = @import("hissybitz").ulid.Ulid;

const std_logger = std.log.scoped(.hissylogz_logger);

const Self = @This();

const LogEntryPool = std.ArrayList(*LogEntry);

const num_log_levels = 6;
// const num_log_levels = @typeInfo(LogLevel).@"enum".fields.len; // FIXME - Something along these lines

name: []const u8,
allocator: std.mem.Allocator,
entry_pools: []LogEntryPool,
entry_pools_mutex: std.Thread.Mutex,
output: LogOutput,
output_mutex: *std.Thread.Mutex,
format: LogFormat,
level: LogLevel,
level_filter_ordinal: u3,

pub fn init(name: []const u8, allocator: std.mem.Allocator, options: LogOptions, output_mutex: *std.Thread.Mutex) AllocationError!Self {
    const logger_name = allocator.dupe(u8, name) catch return AllocationError.OutOfMemory;
    errdefer allocator.free(name);

    // Prepare entry pools
    var pools = allocator.alloc(LogEntryPool, num_log_levels) catch return AllocationError.OutOfMemory;
    errdefer allocator.free(pools);
    const level_filter_ordinal = @intFromEnum(options.level);
    for (level_filter_ordinal..@intFromEnum(LogLevel.none)) |idx| {
        pools[idx] = LogEntryPool.initCapacity(allocator, limits.default_initial_log_entry_pool_size) catch |e| {
            std_logger.err("Failed to create log entry pool: {any}", .{e});
            std_logger.debug("Falling back to no-op log entry.", .{});
            return AllocationError.OutOfMemory;
        };
    }

    // Create self
    return .{
        .name = logger_name,
        .allocator = allocator,
        .entry_pools = pools,
        .entry_pools_mutex = .{},
        .output = options.output,
        .level = options.level,
        .output_mutex = output_mutex,
        .format = options.format,
        .level_filter_ordinal = level_filter_ordinal,
    };
}

pub fn deinit(self: *Self) void {
    defer self.allocator.free(self.name);
    defer self.allocator.free(self.entry_pools);

    self.entry_pools_mutex.lock();
    defer self.entry_pools_mutex.unlock();

    for (self.level_filter_ordinal..@intFromEnum(LogLevel.none)) |idx| {
        defer self.entry_pools[idx].deinit();
        for (self.entry_pools[idx].items) |log_entry| {
            defer self.allocator.destroy(log_entry);
            log_entry.deinit();
        }
    }
}

pub inline fn fine(self: *Self) *LogEntry {
    var le = acquireEntry(self, .fine) catch return &noop_log_entry;
    return le.name(self.name);
}

pub inline fn debug(self: *Self) *LogEntry {
    var le = acquireEntry(self, .debug) catch return &noop_log_entry;
    return le.name(self.name);
}

pub inline fn info(self: *Self) *LogEntry {
    var le = acquireEntry(self, .info) catch return &noop_log_entry;
    return le.name(self.name);
}

pub inline fn warn(self: *Self) *LogEntry {
    var le = acquireEntry(self, .warn) catch return &noop_log_entry;
    return le.name(self.name);
}

pub inline fn err(self: *Self) *LogEntry {
    var le = acquireEntry(self, .err) catch return &noop_log_entry;
    return le.name(self.name);
}

pub inline fn fatal(self: *Self) *LogEntry {
    var le = acquireEntry(self, .fatal) catch return &noop_log_entry;
    return le.name(self.name);
}

fn acquireEntry(self: *Self, level: LogLevel) AllocationError!*LogEntry {
    if (@intFromEnum(level) < self.level_filter_ordinal) {
        return &noop_log_entry;
    }

    self.entry_pools_mutex.lock();
    defer self.entry_pools_mutex.unlock();

    var pool = &self.entry_pools[@intFromEnum(level)];
    var entry = pool.popOrNull() orelse {
        const new_entry = self.allocator.create(LogEntry) catch |e| {
            std_logger.err("Failed to acquire log entry: {any}", .{e});
            std_logger.debug("Falling back to no-op log entry.", .{});
            return AllocationError.OutOfMemory;
        };
        errdefer self.allocator.destroy(new_entry);

        new_entry.* = try self.createLogEntry(level);

        return new_entry;
    };

    entry.reset();
    return entry;
}

fn releaseEntry(self: *Self, entry: *LogEntry) void {
    self.entry_pools_mutex.lock();
    defer self.entry_pools_mutex.unlock();

    var pool = &self.entry_pools[@intFromEnum(entry.level())];
    pool.append(entry) catch |e| {
        std_logger.err("Failed to release log entry: {any}", .{e});
        return;
    };
}

fn createLogEntry(self: *Self, level: LogLevel) AllocationError!LogEntry {
    return switch (self.format) {
        .json => {
            return LogEntry.init(.{ .json = .{
                .json_appender = try JsonAppender.init(self.allocator, self.output, self.output_mutex, level, Timestamp.now()),
                .logger = self,
            } });
        },
        .text => {
            return LogEntry.init(.{ .text = .{
                .text_appender = try TextAppender.init(self.allocator, self.output, self.output_mutex, level, Timestamp.now()),
                .logger = self,
            } });
        },
    };
}

const TextAppender = @import("TextAppender.zig");
const TextAppenderCtx = struct {
    logger: *Logger,
    text_appender: TextAppender,
};

const JsonAppender = @import("JsonAppender.zig");
const JsonAppenderCtx = struct {
    logger: *Logger,
    json_appender: JsonAppender,
};

const Appender = union(enum) {
    noop: LogLevel,
    json: JsonAppenderCtx,
    text: TextAppenderCtx,
};

pub const LogEntry = struct {
    appender: Appender,

    inline fn init(appender: Appender) LogEntry {
        return .{
            .appender = appender,
        };
    }

    inline fn deinit(self: *LogEntry) void {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.deinit(),
            .text => |*tctx| tctx.text_appender.deinit(),
        }
    }

    pub inline fn level(self: *const LogEntry) LogLevel {
        return switch (self.appender) {
            .noop => |lvl| lvl,
            .json => |*jctx| jctx.json_appender.level,
            .text => |*tctx| tctx.text_appender.level,
        };
    }

    pub inline fn log(self: *LogEntry) void {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| {
                defer jctx.logger.releaseEntry(self);
                jctx.json_appender.log();
            },
            .text => |*tctx| {
                defer tctx.logger.releaseEntry(self);
                tctx.text_appender.log();
            },
        }
    }

    pub inline fn ctx(self: *LogEntry, value: []const u8) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.ctx(value),
            .text => |*tctx| tctx.text_appender.ctx(value),
        }
        return self;
    }

    pub inline fn src(self: *LogEntry, value: std.builtin.SourceLocation) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.src(value),
            .text => |*tctx| tctx.text_appender.src(value),
        }
        return self;
    }

    pub inline fn msg(self: *LogEntry, opt_value: ?[]const u8) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.msg(opt_value),
            .text => |*tctx| tctx.text_appender.msg(opt_value),
        }
        return self;
    }

    pub inline fn name(self: *LogEntry, opt_value: ?[]const u8) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.name(opt_value),
            .text => |*tctx| tctx.text_appender.name(opt_value),
        }
        return self;
    }

    pub inline fn str(self: *LogEntry, key: []const u8, opt_value: ?[]const u8) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.str(key, opt_value),
            .text => |*tctx| tctx.text_appender.str(key, opt_value),
        }
        return self;
    }

    pub inline fn strZ(self: *LogEntry, key: []const u8, opt_value: ?[*:0]const u8) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.strZ(key, opt_value),
            .text => |*tctx| tctx.text_appender.strZ(key, opt_value),
        }
        return self;
    }

    pub inline fn ulid(self: *LogEntry, key: []const u8, opt_value: ?Ulid) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.ulid(key, opt_value),
            .text => |*tctx| tctx.text_appender.ulid(key, opt_value),
        }
        return self;
    }

    pub inline fn int(self: *LogEntry, key: []const u8, value: anytype) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.int(key, value),
            .text => |*tctx| tctx.text_appender.int(key, value),
        }
        return self;
    }

    pub inline fn intx(self: *LogEntry, key: []const u8, value: anytype) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.intx(key, value),
            .text => |*tctx| tctx.text_appender.intx(key, value),
        }
        return self;
    }

    pub inline fn float(self: *LogEntry, key: []const u8, value: anytype) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.float(key, value),
            .text => |*tctx| tctx.text_appender.float(key, value),
        }
        return self;
    }

    pub inline fn boolean(self: *LogEntry, key: []const u8, value: anytype) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.boolean(key, value),
            .text => |*tctx| tctx.text_appender.boolean(key, value),
        }
        return self;
    }

    pub inline fn obj(self: *LogEntry, key: []const u8, value: anytype) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.obj(key, value),
            .text => |*tctx| tctx.text_appender.obj(key, value),
        }
        return self;
    }

    pub inline fn binary(self: *LogEntry, key: []const u8, opt_value: ?[]const u8) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.binary(key, opt_value),
            .text => |*tctx| tctx.text_appender.binary(key, opt_value),
        }
        return self;
    }

    pub inline fn err(self: *LogEntry, value: anyerror) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.err(value),
            .text => |*tctx| tctx.text_appender.err(value),
        }
        return self;
    }

    pub inline fn errK(self: *LogEntry, key: []const u8, value: anyerror) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.errK(key, value),
            .text => |*tctx| tctx.text_appender.errK(key, value),
        }
        return self;
    }

    pub inline fn trace(self: *LogEntry, opt_value: ?[]const u8) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.fine(opt_value),
            .text => |*tctx| tctx.text_appender.fine(opt_value),
        }
        return self;
    }

    pub inline fn span(self: *LogEntry, opt_value: ?[]const u8) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.span(opt_value),
            .text => |*tctx| tctx.text_appender.span(opt_value),
        }
        return self;
    }

    pub inline fn fmt(self: *LogEntry, key: []const u8, comptime format: []const u8, values: anytype) *LogEntry {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.fmt(key, format, values),
            .text => |*tctx| tctx.text_appender.fmt(key, format, values),
        }
        return self;
    }

    inline fn reset(self: *LogEntry) void {
        switch (self.appender) {
            .noop => {},
            .json => |*jctx| jctx.json_appender.reset(),
            .text => |*tctx| tctx.text_appender.reset(),
        }
    }
};

const noop_appender: Appender = .{ .noop = .none };
var noop_log_entry = LogEntry.init(noop_appender);

const Logger = @This();

test "logger - smoke test" {
    std.debug.print("logger - smoke test\n", .{});
    const allocator = testing.allocator;

    var werr = std.io.getStdErr().writer();
    const output: LogOutput = .{
        .writer = &werr,
    };
    var mtx: std.Thread.Mutex = .{};

    var json_logger = try Logger.init("json smoke test", allocator, .{
        .format = .json,
        .level = .debug,
        .output = output,
    }, &mtx);
    defer json_logger.deinit();

    try _tst_smoke_logger(&json_logger);

    var text_logger = try Logger.init("text smoke test", allocator, .{
        .format = .text,
        .level = .debug,
        .output = output,
    }, &mtx);
    defer text_logger.deinit();

    try _tst_smoke_logger(&text_logger);
}

fn _tst_smoke_logger(logger: *Logger) !void {
    logger.debug().msg("debug smoke test").log();
    logger.info().msg("info smoke test").log();

    var entry_1 = logger.info().msg("info entry 1");
    var entry_2 = logger.info().msg("info entry 2");

    entry_1.log();
    entry_2.log();

    logger.info().src(@src()).int("one", 1).log();
    logger.info().src(@src()).str("useful", "perhaps").log();
    logger.warn().str("dire", "warning").log();
    logger.warn().intx("failures", 65).log();

    const ulid = @import("hissybitz").ulid;
    var id_gen = ulid.generator();
    const id = try id_gen.next();

    logger.warn().ulid("id", id).log();
}

// ---
// hissylogz.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
