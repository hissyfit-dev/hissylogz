//! hissylogz base32 utility functions.

const std = @import("std");

/// Crockford base-32 Aphabet.
pub const Alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
comptime {
    if (Alphabet.len != 32) @compileError("Bad alphabet");
}

pub fn alphaIdx(c: u8) ?u8 {
    const alpha_idxs = comptime blk: {
        var idxs: [256]?u8 = undefined;
        for (0..256) |i| idxs[i] = _alphaIdx(i);
        break :blk idxs;
    };
    return alpha_idxs[c];
}

fn _alphaIdx(c: u8) ?u8 {
    return switch (c) {
        inline 0...47 => null,
        inline '0'...'9' => |i| i - 48,
        inline 58...64 => null,
        inline 'A'...'H' => |i| i - 65 + 10,
        inline 'I' => null,
        inline 'J'...'K' => |i| i - 65 + 10 - 1,
        inline 'L' => null,
        inline 'M'...'N' => |i| i - 65 + 10 - 2,
        inline 'O' => null,
        inline 'P'...'T' => |i| i - 65 + 10 - 3,
        inline 'U' => null,
        inline 'V'...'Z' => |i| i - 65 + 10 - 4,
        inline 91...255 => null,
    };
}
