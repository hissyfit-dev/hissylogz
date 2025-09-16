//! hissylogz - Logging timestamp

const std = @import("std");
const testing = std.testing;

const IntFittingRange = std.math.IntFittingRange;

/// Timestamp
const Self = @This();

utc_ts: DateTime,

/// Initialize from nanos since Unix epoch.
///
/// Unix epoch is: 1971-01-01T00:00:00Z
pub inline fn init(epoch_nanos: i128) Self {
    return .{ .utc_ts = DateTime.fromNanos(epoch_nanos) };
}

pub inline fn now() Self {
    return init(std.time.nanoTimestamp());
}

pub fn format(self: @This(), writer: *std.io.Writer) std.io.Writer.Error!void {
    try self.utc_ts.format(writer);
}

/// Represents a date and time with timezone offset.
///
/// Vendored in and modified a tiny subset of https://github.com/dylibso/datetime-zig under BSD license
const DateTime = struct {
    /// Calendar year (e.g., 2023)
    year: u16,
    /// Month of the year (1-12)
    month: u8,
    /// Day of the month (1-31)
    day: u8,
    /// Hour of the day (0-23)
    hour: u8,
    /// Minute of the hour (0-59)
    minute: u8,
    /// Second of the minute (0-60, allowing for leap seconds)
    second: u8,
    /// Subseconds (0-999999)
    subseconds: u64,
    /// Timezone offset in minutes from UTC
    offset: i16,

    fn getOffsetSign(offset: i16) u8 {
        return if (offset < 0) '-' else '+';
    }

    /// Renders self to writer in RFC 3339 format
    pub fn format(self: DateTime, writer: *std.io.Writer) std.io.Writer.Error!void {
        // Write the date and time components
        writer.print("{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0>6}", .{
            self.year,                            self.month,  self.day,
            self.hour,                            self.minute, self.second,
            self.subseconds / std.time.ns_per_us,
        }) catch unreachable;

        // Write the timezone offset
        if (self.offset == 0) {
            writer.writeAll("Z") catch unreachable;
        } else {
            const abs_offset = @abs(self.offset);
            const offset_hours = @divFloor(abs_offset, 60);
            const offset_minutes = @mod(abs_offset, 60);
            writer.print("{c}{d:0>2}:{d:0>2}", .{
                getOffsetSign(self.offset),
                offset_hours,
                offset_minutes,
            }) catch unreachable;
        }
    }

    /// Creates a DateTime from Unix timestamp in milliseconds
    /// Note: This function assumes UTC (offset 0)
    // largely constructed from https://www.aolium.com/karlseguin/cf03dee6-90e1-85ac-8442-cf9e6c11602a
    pub fn fromNanos(ns: i128) DateTime {
        const ts: u64 = @intCast(@divTrunc(ns, std.time.ns_per_s));
        const SECONDS_PER_DAY = std.time.s_per_day;
        const DAYS_PER_YEAR = 365;
        const DAYS_IN_4YEARS = 1461;
        const DAYS_IN_100YEARS = 36524;
        const DAYS_IN_400YEARS = 146097;
        const DAYS_BEFORE_EPOCH = 719468;

        const seconds_since_midnight: u64 = @rem(ts, SECONDS_PER_DAY);
        var day_n: u64 = DAYS_BEFORE_EPOCH + ts / SECONDS_PER_DAY;
        var temp: u64 = 0;

        temp = 4 * (day_n + DAYS_IN_100YEARS + 1) / DAYS_IN_400YEARS - 1;
        var year: u16 = @intCast(100 * temp);
        day_n -= DAYS_IN_100YEARS * temp + temp / 4;

        temp = 4 * (day_n + DAYS_PER_YEAR + 1) / DAYS_IN_4YEARS - 1;
        year += @intCast(temp);
        day_n -= DAYS_PER_YEAR * temp + temp / 4;

        var month: u8 = @intCast((5 * day_n + 2) / 153);
        const day: u8 = @intCast(day_n - (@as(u64, @intCast(month)) * 153 + 2) / 5 + 1);

        month += 3;
        if (month > 12) {
            month -= 12;
            year += 1;
        }

        return DateTime{ .year = year, .month = month, .day = day, .hour = @intCast(seconds_since_midnight / 3600), .minute = @intCast(seconds_since_midnight % 3600 / 60), .second = @intCast(seconds_since_midnight % 60), .subseconds = @intCast(@rem(ns, std.time.ns_per_s)), .offset = 0 };
    }
};
