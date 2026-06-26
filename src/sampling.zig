const std = @import("std");

const math = @import("math.zig");
const random = @import("random.zig");

const add = math.add;
const sub = math.sub;
const mul = math.mul;
const dot = math.dot;
const mag = math.mag;
const Vec3 = math.Vec3;
const cross = math.cross;
const normalize = math.normalize;

/// Generates an arbitrary set of local coordinate axes such that the input normal vector is on the
/// z-axis, all axes are normalized, and the coordinate system is right-handed.
/// NOTE: The input normal vector MUST be normalized for correct results.
pub fn buildCoordinateAxes(n: Vec3) struct { Vec3, Vec3, Vec3 } {
    std.debug.assert(std.math.approxEqRel(f32, mag(n), 1.0, 4.0 * math.eps));
    const z: Vec3 = n;
    const y: Vec3 = normalize(cross(z, if (@abs(z[0]) < 0.9) math.unit_x else math.unit_y));
    const x: Vec3 = cross(y, z);
    return .{ x, y, z };
}

test "buildLocalCoordinateAxes --- is right handed" {
    const x, const y, const z = buildCoordinateAxes(
        normalize(@as(Vec3, .{ -1.0, 2.71, 3.14 })),
    );
    try std.testing.expectApproxEqRel(1.0, dot(cross(x, y), z), 4.0 * math.eps);
}

test "buildLocalCoordinateAxes --- is normalized" {
    const x, const y, const z = buildCoordinateAxes(
        normalize(@as(Vec3, .{ -1.0, 2.71, 3.14 })),
    );
    try std.testing.expectApproxEqRel(1.0, mag(x), 4.0 * math.eps);
    try std.testing.expectApproxEqRel(1.0, mag(y), 4.0 * math.eps);
    try std.testing.expectApproxEqRel(1.0, mag(z), 4.0 * math.eps);
}

pub const BRDFSample = struct {
    dir: Vec3,
    p: f32,
};

/// Cosine-weighted hemisphere sampling using Malley's method... sortof.
/// Really this function samples the light transport equation integrand assuming a Lambertian BRDF
/// and constant incoming radiance.
/// NOTE: The input normal vector MUST be normalized for correct results.
pub fn sampleLambertianBRDF(n: Vec3, rng: *random.PCGHash) BRDFSample {
    std.debug.assert(std.math.approxEqRel(f32, mag(n), 1.0, 4.0 * math.eps));
    const r: f32 = @sqrt(rng.float32());
    const t: f32 = 2.0 * std.math.pi * rng.float32();
    const x: f32 = r * @cos(t);
    const y: f32 = r * @sin(t);
    const z: f32 = @sqrt(@max(1.0 - x * x - y * y, 0.0));
    const x_axis, const y_axis, const z_axis = buildCoordinateAxes(n);
    const d = normalize(add(add(mul(x_axis, x), mul(y_axis, y)), mul(z_axis, z)));
    return .{ .dir = d, .p = dot(d, n) / std.math.pi };
}

test "sampleLambertianBRDF --- is cosine weighted" {
    var rng = random.PCGHash{ .state = @as(u32, @intCast(42)) };
    var nlo: usize = 0;
    var nhi: usize = 0;
    for (1..(1 << 10)) |_| {
        const dir: Vec3 = sampleLambertianBRDF(.{ 0.0, 0.0, 1.0 }, &rng).dir;
        if (dir[2] > comptime @sqrt(0.5)) nhi += 1 else nlo += 1;
    }
    const hifrac = @as(f32, @floatFromInt(nhi)) / @as(f32, @floatFromInt(nlo + nhi));
    try std.testing.expectApproxEqRel(0.5, hifrac, 0.01);
}

/// Computes specular reflection given a normal vector, and a vector "w" pointing toward the light
/// source (this is the opposite of the light's travel direction).
pub fn sampleSpecularBRDF(n: Vec3, w: Vec3) BRDFSample {
    return .{ .dir = normalize(sub(mul(2.0, mul(dot(n, w), n)), w)), .p = 1.0 };
}

test "sampleSpecularBRDF --- correct direction" {
    const n: Vec3 = normalize(.{ -1.0, 0.0, -1.0 });
    const w: Vec3 = normalize(.{ 0.0, 0.0, -1.0 });
    const r: Vec3 = sampleSpecularBRDF(n, w).dir;
    try std.testing.expectApproxEqRel(-1.0, r[0], 4.0 * math.eps);
    try std.testing.expectApproxEqAbs(0.0, r[1], 4.0 * math.eps);
    try std.testing.expectApproxEqAbs(0.0, r[2], 4.0 * math.eps);
}

test "sampleSpecularBRDF --- equal dot product" {
    const n: Vec3 = normalize(.{ -1.0, -1.0, -1.0 });
    const w: Vec3 = normalize(.{ 3.0, 2.0, 1.0 });
    const r: Vec3 = sampleSpecularBRDF(n, w).dir;
    try std.testing.expectApproxEqRel(dot(n, w), dot(n, r), 4.0 * math.eps);
}
