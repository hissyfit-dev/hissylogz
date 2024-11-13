//! hissylogz constants.

const std = @import("std");

pub const hissylogz_version: std.SemanticVersion = .{ .major = 0, .minor = 0, .patch = 1 };

/// Timestamp
const datetime = @import("datetime");
pub const Timestamp = datetime.datetime.Advanced(datetime.Date, datetime.time.Nano, false);

/// Logging format
pub const LogFormat = enum {
    json,
    text,
};

/// Logging output
pub const LogOutput = struct {
    writer: *std.fs.File.Writer,
    mutex: std.Thread.Mutex,
};

/// Logging level
pub const LogLevel = enum(u3) {
    trace,
    debug,
    info,
    warn,
    err,
    fatal,
    none,

    pub fn parse(input: []const u8) ?LogLevel {
        if (input.len < 4 or input.len > 5) return null;
        var buf: [5]u8 = undefined;

        const lower = std.ascii.lowerString(&buf, input);
        if (std.mem.eql(u8, lower, "trace")) return .trace;
        if (std.mem.eql(u8, lower, "debug")) return .debug;
        if (std.mem.eql(u8, lower, "info")) return .info;
        if (std.mem.eql(u8, lower, "warn")) return .warn;
        if (std.mem.eql(u8, lower, "err")) return .err;
        if (std.mem.eql(u8, lower, "fatal")) return .fatal;
        if (std.mem.eql(u8, lower, "none")) return .none;
        return null;
    }
};

/// Logging options
pub const LogOptions = struct {
    level: LogLevel = .info,
    format: LogFormat = .json,
    output: LogOutput,
};

// ---
// hissylogz.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
