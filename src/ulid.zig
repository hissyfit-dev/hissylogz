//! ULID implementation.

const std = @import("std");

const base32 = @import("base32.zig");

pub const OverflowError = error{
    TimeOverflow,
    RandomOverflow,
};

pub const DecodeError = error{
    DecodeWrongSize,
    DecodeBadChar,
};

pub const AllocationError = error{
    OutOfMemory,
};

pub const UsageError = error{WrongBufferSize};

pub const binary_length = 16;
pub const text_length = 26;

/// ULID (Universally Unique Lexicographically Sortable Identifier) to overlay u128
///
/// See [ULID](https://github.com/ulid/spec)
pub const Ulid = packed struct {
    const text_time_bytes = 10;
    const text_rand_bytes = 16;
    const Self = @This();

    time: u48,
    rand: u80,

    pub fn asInt(self: Self) u128 {
        return @bitCast(self);
    }

    pub fn bytes(self: Self) [binary_length]u8 {
        return @bitCast(self);
    }

    pub fn encode(self: Self) [text_length]u8 {
        var out: [text_length]u8 = undefined;
        self.encodeBuf(&out) catch unreachable;
        return out;
    }

    pub fn encodeAlloc(self: Self, allocator: std.mem.Allocator) AllocationError![]u8 {
        const out = allocator.alloc(u8, text_length) catch return AllocationError.OutOfMemory;
        self.encodeBuf(out) catch unreachable;
        return out;
    }

    pub fn encodeBuf(self: Self, out: []u8) UsageError!void {
        if (out.len != text_length) return UsageError.WrongBufferSize;

        // encode time
        {
            const base: u48 = base32.Alphabet.len;
            var trem: u48 = self.time;

            inline for (0..text_time_bytes) |i| {
                const val = @rem(trem, base);
                trem >>= 5;
                out[text_time_bytes - 1 - i] = base32.Alphabet[@intCast(val)];
            }
        }

        // encode rand
        {
            const base: u80 = base32.Alphabet.len;
            var rrem: u80 = self.rand;

            inline for (0..text_rand_bytes) |i| {
                const val = @rem(rrem, base);
                rrem >>= 5;
                out[text_time_bytes + text_rand_bytes - 1 - i] = base32.Alphabet[@intCast(val)];
            }
        }
    }

    pub fn equals(self: Self, other: Self) bool {
        const s = @as(u128, @bitCast(self));
        const o = @as(u128, @bitCast(other));
        return s == o;
    }

    pub fn format(value: Self, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        _ = try writer.write(&value.encode());
    }
};

pub fn fromBytes(buf: []const u8) UsageError!Ulid {
    if (buf.len != binary_length) return UsageError.WrongBufferSize;
    const bufl = buf[0..binary_length].*;
    return @bitCast(bufl);
}

pub fn decode(s: []const u8) DecodeError!Ulid {
    if (s.len != text_length) return DecodeError.DecodeWrongSize;

    var time: u48 = 0;
    inline for (0..Ulid.text_time_bytes) |i| {
        const maybe_idx = base32.alphaIdx(s[i]);
        if (maybe_idx) |idx| {
            time |= @as(u48, @intCast(idx)) << @as(u48, @intCast(5 * (Ulid.text_time_bytes - 1 - i)));
        } else {
            return DecodeError.DecodeBadChar;
        }
    }

    var rand: u80 = 0;
    inline for (0..Ulid.text_rand_bytes) |i| {
        const maybe_idx = base32.alphaIdx(s[Ulid.text_time_bytes + i]);
        if (maybe_idx) |idx| {
            rand |= @as(u80, @intCast(idx)) << @as(u80, @intCast(5 * (Ulid.text_rand_bytes - 1 - i)));
        } else {
            return DecodeError.DecodeBadChar;
        }
    }

    return .{ .time = time, .rand = rand };
}

pub const GeneratorError = error{
    TimeTooOld,
    TimeOverflow,
    RandomOverflow,
};

pub const Generator = struct {
    r: std.rand.Random = std.crypto.random,
    last: Ulid = .{ .time = 0, .rand = 0 },

    pub fn next(self: *@This()) GeneratorError!Ulid {
        const ms = std.time.milliTimestamp();
        if (ms < 0) return GeneratorError.TimeTooOld;
        if (ms > std.math.maxInt(u48)) return GeneratorError.TimeOverflow;
        const ms48: u48 = @intCast(ms);

        if (ms48 == self.last.time) {
            if (self.last.rand == std.math.maxInt(u80)) return GeneratorError.RandomOverflow;
            self.last.rand += 1;
        } else {
            self.last.time = ms48;
            self.last.rand = self.r.int(u80);
        }

        return self.last;
    }
};

pub fn generator() Generator {
    return .{};
}

test "ulid" {
    var gen = generator();

    _ = try gen.next();
    const id0 = try gen.next();
    const id1 = try gen.next();

    // timestamp 48 bits
    try std.testing.expectEqual(@bitSizeOf(@TypeOf(id0.time)), 48);
    // randomness 80 bits
    try std.testing.expectEqual(@bitSizeOf(@TypeOf(id0.rand)), 80);
    // timestamp is milliseconds since unix epoch
    try std.testing.expect((std.time.milliTimestamp() - id0.time) < 10);

    // uses crockford base32 alphabet
    const str = id0.encode();
    try std.testing.expectEqual(str.len, text_length);
    for (0..str.len) |i| {
        try std.testing.expect(std.mem.indexOf(u8, base32.Alphabet, str[i .. i + 1]) != null);
    }
    try std.testing.expectEqualDeep(try decode(&str), id0);
    const str_alloc = try id0.encodeAlloc(std.testing.allocator);
    defer std.testing.allocator.free(str_alloc);
    try std.testing.expect(std.mem.eql(u8, str_alloc, &str));

    // monotonic in the same millisecond
    try std.testing.expectEqual(id0.time, id1.time);
    try std.testing.expect(id0.rand != id1.rand);
    try std.testing.expectEqual(id0.rand + 1, id1.rand);

    // binary encodable
    const bytes = id0.bytes();
    const time_bytes = bytes[0..6].*;
    const rand_bytes = bytes[6..].*;
    try std.testing.expectEqual(@as(u48, @bitCast(time_bytes)), id0.time);
    try std.testing.expectEqual(@as(u80, @bitCast(rand_bytes)), id0.rand);
    try std.testing.expect((try fromBytes(&bytes)).equals(id0));
}

// ---
// hissylogz.
//
// Parts of this file contain code re-purposed frrom code under the 0BSD license.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
