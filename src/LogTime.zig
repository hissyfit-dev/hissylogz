//! hissylogz - Logging timestamp

const std = @import("std");
const testing = std.testing;

/// Timestamp
const datetime = @import("datetime");
const UtcTimestamp = datetime.datetime.Advanced(datetime.Date, datetime.time.Micro, false);

const Self = @This();

utc_ts: UtcTimestamp,

/// Creates a log time (UTC timestamp) using the given number of nanoseconds since or before (negative) UNIX epoch.
///
/// UNIX epoch is: 1971-01-01T00:00:00Z
pub fn init(epoch_nanos: i128) Self {
    const days = @divFloor(epoch_nanos, std.time.ns_per_day);
    const new_date = UtcTimestamp.Date.fromEpoch(@intCast(days));
    const day_nanos = std.math.comptimeMod(epoch_nanos, std.time.ns_per_day);
    // fromDaySeconds() is a misnomer, it takes subseconds, in this case, microseconds
    const new_time = UtcTimestamp.Time.fromDaySeconds(@intCast(@divFloor(day_nanos, std.time.ns_per_us)));
    const utc_ts: UtcTimestamp = .{
        .date = new_date,
        .time = new_time,
    };
    return .{ .utc_ts = utc_ts };
}

pub inline fn now() Self {
    return init(std.time.nanoTimestamp());
}

pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) (@TypeOf(writer).Error || error{Range})!void {
    try writer.print("{rfc3339}T{d:0>2}:{d:0>2}:{d:0>2}.{d:0<6}Z", .{
        self.utc_ts.date,
        self.utc_ts.time.hour,
        self.utc_ts.time.minute,
        self.utc_ts.time.second,
        self.utc_ts.time.subsecond,
    });
}
