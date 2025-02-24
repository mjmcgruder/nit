const std = @import("std");

const m = @import("math.zig");

/// Nathan Reed, Hash Functions for GPU Rendering
///   https://www.reedbeta.com/blog/hash-functions-for-gpu-rendering/
/// This struct is intended to provide thread-local state for the random number generator. There
/// should be one instance per thread, not one for the entire program (TODO: why?).
pub const PCGHash = struct {
    state: u32,

    /// Returns a random unsigned 32 bit integer.
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

pub const CoordinateAxes = struct {
    x: m.Vec3 = .{ .x = 1.0, .y = 0.0, .z = 0.0 },
    y: m.Vec3 = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
    z: m.Vec3 = .{ .x = 0.0, .y = 0.0, .z = 1.0 },
};

/// Generates an arbitrary set of local coordinate axes such that the input normal vector is on the
/// z-axis, all axes are normalized, and the coordinate system is right-handed.
pub fn localCoordinateAxes(n: m.Vec3) CoordinateAxes {
    var local: CoordinateAxes = .{};
    local.z = n;
    local.y = m.normalize(m.cross(local.z, if (@abs(local.z.x) < 0.9) m.unit_x else m.unit_y));
    local.x = m.normalize(m.cross(local.y, local.z));
    return local;
}

/// This function is modified from the sphere point picking algorithm from Wolfram Math World.
///   https://mathworld.wolfram.com/SpherePointPicking.html
/// The only modification is "u" is chosen on the range [0.0, 1.0] instead of [-1.0, 1.0]. This
/// turns random sphere point picking into random hemisphere point picking. The coordinate system
/// for the random point picking is also arbitrarily chosen, this should not have any negative
/// impact to my knowledge.
pub fn randomRayInHemisphere(n: m.Vec3, rng: *PCGHash) m.Vec3 {
    const t: f32 = rng.float32() * 2.0 * std.math.pi;
    const u: f32 = rng.float32();
    const r: f32 = @sqrt(1.0 - u * u);
    const x: f32 = r * @cos(t);
    const y: f32 = r * @sin(t);
    const z: f32 = u;
    const local: CoordinateAxes = localCoordinateAxes(n);
    return m.normalize(m.add(m.add(m.mul(local.x, x), m.mul(local.y, y)), m.mul(local.z, z)));
}

/// Computes specular reflection given a normal vector, and a vector "w" pointing toward the light
/// source (this is the opposite of the light's travel direction).
pub fn specularReflection(n: m.Vec3, w: m.Vec3) m.Vec3 {
    return m.normalize(m.sub(m.mul(2.0, m.mul(m.dot(n, w), n)), w));
}
