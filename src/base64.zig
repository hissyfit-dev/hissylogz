//! hissylogz base64 utility functions.

const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const builtin = @import("builtin");
const native_os = builtin.os.tag;
const base64 = std.base64;

const base64_codec = base64.url_safe_no_pad;

/// Base64 Errors
const Error = error{
    /// An invalid argument was passed
    InvalidArgument,
    /// Memory allocation failed
    OutOfMemory,
};

/// Decodes a Base-64 `encoded` value and returns a decoded slice, allocated using `allocator`.
///
/// It's the caller's responsibility to free the decoded slice.
///
/// Note: By default, we use a URL-safe, non-padding codec.
pub fn decode(allocator: std.mem.Allocator, encoded: []const u8) Error![]const u8 {
    const size = base64_codec.Decoder.calcSizeForSlice(encoded) catch return error.InvalidArgument;
    const decoded = allocator.alloc(u8, size) catch return Error.OutOfMemory;
    errdefer allocator.free(decoded);
    base64_codec.Decoder.decode(decoded, encoded) catch return Error.InvalidArgument;
    return decoded;
}

/// Encodes an `unencoded` value, and returns a Base-64 encoded slice, allocated using `allocator`.
///
/// It's the caller's responsibility to free the encoded slice.
///
/// Note: By default, we use a URL-safe, non-padding codec.
pub fn encode(allocator: std.mem.Allocator, unencoded: []const u8) Error![]const u8 {
    const size = base64_codec.Encoder.calcSize(unencoded.len);
    const encoded = allocator.alloc(u8, size) catch return Error.OutOfMemory;
    errdefer allocator.free(encoded);
    _ = base64_codec.Encoder.encode(encoded, unencoded);
    return encoded;
}

test "encode and decode base64" {
    const allocator = std.testing.allocator;
    std.debug.print("base64 encoding and decoding\n", .{});

    const original: []const u8 = "Payload text";
    std.debug.print("\toriginal={s}\n", .{original});

    const encoded = try encode(allocator, original);
    defer allocator.free(encoded);
    std.debug.print("\tencoded={s}\n", .{encoded});

    const decoded = try decode(allocator, encoded);
    defer allocator.free(decoded);
    std.debug.print("\tdecoded={s}\n", .{decoded});

    try testing.expectEqualSlices(u8, original, decoded);

    if (decode(allocator, "Garbage")) |gigo| {
        std.debug.print("\tgigo={s}\n", .{gigo});
        defer allocator.free(gigo);
    } else |err| {
        try testing.expect(Error.InvalidArgument == err);
    }
}

// ---
// hissylogz.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
