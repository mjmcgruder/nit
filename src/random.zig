const std = @import("std");

/// Source: Hash Functions for GPU Rendering - Nathan Reed
///   https://www.reedbeta.com/blog/hash-functions-for-gpu-rendering/
/// This struct is intended to provide thread-local state for the random number generator. There
/// should be one instance per thread, not one for the entire program (TODO: why?).
pub const PCGHash = struct {
    state: u32,

    /// Returns a pseudorandom unsigned 32 bit integer.
    pub fn uint32(this: *PCGHash) u32 {
        const state: u32 = this.state;
        this.state = this.state *% 747796405 +% 2891336453;
        const word: u32 = ((state >> (@as(u5, @intCast((state >> 28) + 4)))) ^ state) *% 277803737;
        return (word >> 22) ^ word;
    }

    /// Returns a uniformly distributed random float in the interval [0, 1].
    pub fn float32(this: *PCGHash) f32 {
        const inv_max: f32 = comptime 1.0 / @as(comptime_float, @floatFromInt(std.math.maxInt(u32)));
        return @as(f32, @floatFromInt(this.uint32())) * inv_max;
    }
};
