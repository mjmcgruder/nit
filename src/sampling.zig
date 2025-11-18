const std = @import("std");

const m = @import("math.zig");

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

pub const CoordinateAxes = struct {
    x: m.Vec3 = .{ .data = .{ 1.0, 0.0, 0.0 } },
    y: m.Vec3 = .{ .data = .{ 0.0, 1.0, 0.0 } },
    z: m.Vec3 = .{ .data = .{ 0.0, 0.0, 1.0 } },
};

/// Generates an arbitrary set of local coordinate axes such that the input normal vector is on the
/// z-axis, all axes are normalized, and the coordinate system is right-handed.
/// NOTE: the input normal vector MUST be normalized for correct results
pub fn buildCoordinateAxes(n: m.Vec3) CoordinateAxes {
    var local: CoordinateAxes = .{};
    local.z = n;
    local.y = m.normalize(m.cross(local.z, if (@abs(local.z.data[0]) < 0.9) m.unit_x else m.unit_y));
    local.x = m.cross(local.y, local.z);
    return local;
}

/// This function is modified from the sphere point picking algorithm from Wolfram Math World.
///   https://mathworld.wolfram.com/SpherePointPicking.html
/// The only modification is "u" is chosen on the range [0.0, 1.0] instead of [-1.0, 1.0]. This
/// turns random sphere point picking into random hemisphere point picking. The coordinate system
/// for the random point picking is also arbitrarily chosen, this should not have any negative
/// impact to my knowledge.
/// NOTE: the input normal vector MUST be normalized for correct results
pub fn sampleHemisphere(n: m.Vec3, rng: *PCGHash) m.Vec3 {
    const t: f32 = rng.float32() * 2.0 * std.math.pi;
    const u: f32 = rng.float32();
    const r: f32 = @sqrt(1.0 - u * u);
    const x: f32 = r * @cos(t);
    const y: f32 = r * @sin(t);
    const z: f32 = u;
    const local: CoordinateAxes = buildCoordinateAxes(n);
    return m.normalize(m.add(m.add(m.mul(local.x, x), m.mul(local.y, y)), m.mul(local.z, z)));
}

/// Computes specular reflection given a normal vector, and a vector "w" pointing toward the light
/// source (this is the opposite of the light's travel direction).
pub fn reflect(n: m.Vec3, w: m.Vec3) m.Vec3 {
    return m.normalize(m.sub(m.mul(2.0, m.mul(m.dot(n, w), n)), w));
}

// TESTS -----

test "buildLocalCoordinateAxes --- is right handed" {
    const axes: CoordinateAxes = buildCoordinateAxes(
        m.normalize(.{ .data = .{ -1.0, 2.71, 3.14 } }),
    );
    try std.testing.expectApproxEqRel(1.0, m.dot(m.cross(axes.x, axes.y), axes.z), 10 * m.eps);
}

test "buildLocalCoordinateAxes --- is normalized" {
    const axes: CoordinateAxes = buildCoordinateAxes(
        m.normalize(.{ .data = .{ -1.0, 2.71, 3.14 } }),
    );
    try std.testing.expectApproxEqRel(1.0, m.mag(axes.x), 10 * m.eps);
    try std.testing.expectApproxEqRel(1.0, m.mag(axes.y), 10 * m.eps);
    try std.testing.expectApproxEqRel(1.0, m.mag(axes.z), 10 * m.eps);
}

test "sampleHemisphere --- no polar bias, normalized, hemispherical" {
    const num_samp = 1000000;
    const ray_pole = m.unit_z;
    const ray_othr = m.normalize(m.Vec3{ .data = .{ 1.0, 1.0, 1.0 } });
    const rtol = 1e-2;

    var rng: PCGHash = .{ .state = 42 };
    var tally_pole: usize = 0;
    var tally_othr: usize = 0;
    for (0..num_samp) |_| {
        const ray_samp: m.Vec3 = sampleHemisphere(ray_pole, &rng);
        if ((1.0 - m.dot(ray_samp, ray_pole)) < 0.1) tally_pole += 1;
        if ((1.0 - m.dot(ray_samp, ray_othr)) < 0.1) tally_othr += 1;
        // test overall hemisphere shape on the side
        try std.testing.expect(m.dot(ray_pole, ray_samp) >= 0.0);
        try std.testing.expectApproxEqRel(m.mag(ray_samp), 1.0, 10 * m.eps);
    }

    try std.testing.expectApproxEqRel(
        @as(f64, @floatFromInt(tally_pole)),
        @as(f64, @floatFromInt(tally_othr)),
        rtol,
    );
}

test "reflect --- between axes" {
    const n: m.Vec3 = m.normalize(.{ .data = .{ -1.0, 0.0, -1.0 } });
    const w: m.Vec3 = m.normalize(.{ .data = .{ 0.0, 0.0, -1.0 } });
    const r: m.Vec3 = reflect(n, w);
    try std.testing.expectApproxEqAbs(-1.0, r.data[0], 10 * m.eps);
    try std.testing.expectApproxEqAbs(0.0, r.data[1], 10 * m.eps);
    try std.testing.expectApproxEqAbs(0.0, r.data[2], 10 * m.eps);
}

test "reflect --- equal dot product" {
    var rng: PCGHash = .{ .state = 37 };
    const n: m.Vec3 = m.normalize(.{ .data = .{ -1.0, -1.0, -1.0 } });
    const w: m.Vec3 = sampleHemisphere(n, &rng);
    const r: m.Vec3 = reflect(n, w);
    try std.testing.expectApproxEqRel(m.dot(n, w), m.dot(n, r), 4 * m.eps);
}
