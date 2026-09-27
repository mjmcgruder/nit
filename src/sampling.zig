const std = @import("std");

const math = @import("math.zig");
const rand = @import("random.zig");
const geom = @import("geometry.zig");
const prim = @import("geometry_primitives.zig");

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

pub const Sample = struct {
    dir: Vec3,
    p: f32,
};

inline fn sampleCone(cos_angle: f32, rng: *rand.PCGHash) Sample {
    const tpi: f32 = comptime 2.0 * std.math.pi;
    const omc: f32 = 1.0 - cos_angle;
    const phi: f32 = tpi * rng.float32();
    const cth: f32 = 1.0 - (rng.float32() * omc);
    const sth: f32 = @sqrt(@max(1.0 - cth * cth, 0.0));
    const cph: f32 = @cos(phi);
    const sph: f32 = @sin(phi);
    return .{ .dir = .{ sth * cph, sth * sph, cth }, .p = 1.0 / (tpi * omc) };
}

pub fn sampleSphereLight(p: Vec3, s: prim.Sphere, rng: *rand.PCGHash) Sample {
    const ptoc: Vec3 = sub(s.c, p);
    const samp: Sample = sampleCone(@sqrt(@max(1.0 - ((s.r * s.r) / dot(ptoc, ptoc)), 0.0)), rng);
    const x, const y, const z = buildCoordinateAxes(normalize(ptoc));
    return .{
        .dir = add(add(mul(x, samp.dir[0]), mul(y, samp.dir[1])), mul(z, samp.dir[2])),
        .p = samp.p,
    };
}

test "sampleSphereLight --- unit direction, bounded, no polar bias" {
    var rng = rand.PCGHash{ .state = @as(u32, @intCast(42)) };

    const p = Vec3{ 0.1, 0.2, 0.3 };
    const s = prim.Sphere{ .c = .{ 2.0, 2.2, 0.3 }, .r = 1.2 };

    const ptoc = sub(s.c, p);
    const cntr = normalize(ptoc);
    const sint_max = s.r / mag(ptoc);
    const cost_max = @sqrt(1.0 - sint_max * sint_max);
    const cost_cut = (1.0 + cost_max) / 2.0;

    var nlo: usize = 0;
    var nhi: usize = 0;
    for (1..(1 << 10)) |_| {
        const samp: Sample = sampleSphereLight(p, s, &rng);
        try std.testing.expectApproxEqRel(1.0, mag(samp.dir), 4.0 * math.eps);
        const cost: f32 = dot(cntr, samp.dir);
        try std.testing.expect(cost > cost_max);
        if (cost < cost_cut) {
            nlo += 1;
        } else {
            nhi += 1;
        }
    }
    const hifrac = @as(f32, @floatFromInt(nhi)) / @as(f32, @floatFromInt(nlo + nhi));
    try std.testing.expectApproxEqRel(0.5, hifrac, 0.04);
}

/// Samples the set of light sources in the scene.
/// This function constructs a continuous probability distribution from a discrete distribution over
/// the light sources (evenly weighted at the moment) and a continuous probability distribution over
/// each light source. Notice that discrete and continuous distributions compose nicely since each
/// discrete probability must be less than 1 and the collection sums to one. This turns into a
/// weighted average of continuous distributions (which each integrate to one).
pub fn sampleLights(
    p: Vec3,
    scene: geom.Scene,
    rng: *rand.PCGHash,
) ?struct { Sample, geom.Object } {
    const light: geom.Object = scene.objects[rng.uint32() % @as(u32, @intCast(scene.num_lights))];
    const mPosition = math.transformPos(p, light.itfm);

    const one_light_sample: Sample = switch (light.geom) {
        .sphere => |sphere| sampleSphereLight(mPosition, sphere, rng),
        .mesh => null,
        .box => null,
    } orelse return null;

    const all_light_sample = Sample{
        .dir = math.transformDir(one_light_sample.dir, light.trfm),
        .p = one_light_sample.p / @as(f32, @floatFromInt(scene.num_lights)),
    };

    return .{ all_light_sample, light };
}

/// Cosine-weighted hemisphere sampling using Malley's method... sortof.
/// Really this function samples the light transport equation integrand assuming a Lambertian BRDF
/// and constant incoming radiance.
/// NOTE: The input normal vector MUST be normalized for correct results.
pub fn sampleLambertianBRDF(n: Vec3, rng: *rand.PCGHash) Sample {
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
    var rng = rand.PCGHash{ .state = @as(u32, @intCast(42)) };
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
pub fn sampleSpecularBRDF(n: Vec3, w: Vec3) Sample {
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
