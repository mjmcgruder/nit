const std = @import("std");

const math = @import("math.zig");

const add = math.add;
const sub = math.sub;
const mul = math.mul;
const div = math.div;
const dot = math.dot;
const Vec3 = math.Vec3;
const sdiv = math.sdiv;
const sign = math.sign;
const step = math.step;
const cross = math.cross;
const normalize = math.normalize;

pub const Ray = struct {
    o: Vec3 = @splat(0.0),
    d: Vec3 = @splat(0.0),
};

pub const Sphere = struct {
    c: Vec3 = @splat(0.0),
    r: f32 = 1.0,
};

pub const Box = struct {
    min: Vec3 = @splat(std.math.floatMax(f32)),
    max: Vec3 = @splat(-std.math.floatMax(f32)),
    pub fn grow(self: *Box, point: anytype) void {
        const p: Vec3 = point;
        self.min = @select(f32, p < self.min, p, self.min);
        self.max = @select(f32, p > self.max, p, self.max);
    }
    pub fn size(self: *const Box) Vec3 {
        return mul(0.5, sub(self.max, self.min));
    }
};

pub const Triangle = struct {
    vertices: [3]Vec3,
};

pub const IntersectResult = struct {
    dist: f32 = 0.0,
    norm: Vec3 = .{ 0.0, 0.0, 0.0 },
};

/// Ray-Sphere intersection routine adapted from Inigo Quilez at:
///   https://iquilezles.org/articles/intersectors/
/// This function assumes the sphere is centered at the origin.
pub fn intersectRaySphere(ray: Ray, r: f32) ?IntersectResult {
    const roh: f32 = dot(ray.o, ray.d); // ray origin to half-chord dist
    const woc: Vec3 = sub(ray.o, mul(roh, ray.d)); // world origin to chord vec
    const hsq: f32 = r * r - dot(woc, woc);
    // closest ray point is outside sphere
    if (hsq < 0.0) return null;
    const seh: f32 = @sqrt(hsq); // sphere edge to half-chord distance
    const tn: f32 = -roh - seh; // near
    const tf: f32 = -roh + seh; // far
    // sphere is behind ray origin
    if (tf < 0.0) return null;
    // ray origin is inside sphere
    if (tn < 0.0) {
        return IntersectResult{
            .dist = tf,
            .norm = mul(mul(-1.0, add(ray.o, mul(ray.d, tf))), sdiv(1.0, r)),
        };
    }
    // sphere is ahead of ray origin
    return IntersectResult{
        .dist = tn, // note normalization below is simple since the vector has magnitude radius
        .norm = mul(add(ray.o, mul(ray.d, tn)), sdiv(1.0, r)),
    };
}

test "intersectRaySphere sphere ahead" {
    const ray: Ray = .{ .o = .{ -2.0, 0.0, 0.0 }, .d = .{ 1.0, 0.0, 0.0 } };
    if (intersectRaySphere(ray, 1.0)) |result| {
        try std.testing.expectApproxEqAbs(1.0, result.dist, 4 * math.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm[0], 4 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm[1], 4 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm[2], 4 * math.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRaySphere ray origin inside sphere" {
    const ray: Ray = .{ .o = .{ -0.5, 0.0, 0.0 }, .d = .{ 1.0, 0.0, 0.0 } };
    if (intersectRaySphere(ray, 1.0)) |result| {
        try std.testing.expectApproxEqAbs(1.5, result.dist, 4 * math.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm[0], 4 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm[1], 4 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm[2], 4 * math.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRaySphere sphere behind ray origin" {
    const ray: Ray = .{ .o = .{ 1.5, 0.0, 0.0 }, .d = .{ 1.0, 0.0, 0.0 } };
    if (intersectRaySphere(ray, 1.0)) |_| {
        try std.testing.expect(false);
    } else {
        try std.testing.expect(true);
    }
}

fn intersectRayBoxSlab(ray: Ray, size: Vec3) struct { Vec3, Vec3 } {
    const ird: Vec3 = div(1.0, ray.d); // invserse ray direction
    const dt0: Vec3 = mul(ird, ray.o); // parametric distance to axis-orthogonal plane at 0
    const bdc: Vec3 = mul(@abs(ird), size); // box distance correction
    const atn: Vec3 = sub(mul(-1.0, dt0), bdc); // all near parameters
    const atf: Vec3 = add(mul(-1.0, dt0), bdc); // all far parameters
    return .{ atn, atf };
}

pub fn intersectRayBoxDist(ray: Ray, size: Vec3) ?f32 {
    const atn: Vec3, const atf: Vec3 = intersectRayBoxSlab(ray, size);
    const tn: f32 = @max(atn[0], atn[1], atn[2]);
    const tf: f32 = @min(atf[0], atf[1], atf[2]);
    if (tn > tf or tf < 0.0) return null; // miss or box behind ray origin
    if (tn > 0.0) return tn else return tf;
}

/// Ray-Box intersection routine adapted from Inigo Quilez at:
///   https://iquilezles.org/articles/intersectors/
/// This function (and its sub-functions) assume the box is centered at the origin. The box's "size"
/// is its maximum distance from the origin in each dimension.
pub fn intersectRayBox(ray: Ray, size: Vec3) ?IntersectResult {
    const atn: Vec3, const atf: Vec3 = intersectRayBoxSlab(ray, size);
    const tn: f32 = @max(atn[0], atn[1], atn[2]);
    const tf: f32 = @min(atf[0], atf[1], atf[2]);
    if (tn > tf or tf < 0.0) return null; // miss or box behind ray origin
    if (tn > 0.0) { // hit with box ahead of ray origin
        return .{
            .dist = tn,
            .norm = mul(step(tn, atn), mul(-1.0, sign(ray.d))), // TODO: normalization occasionally slightly incorrect due to FP
        };
    } else { // hit with box ahead of ray origin
        return .{
            .dist = tf,
            .norm = mul(step(atf, tf), mul(-1.0, sign(ray.d))),
        };
    }
}

test "intersectRayBox box ahead" {
    const ray: Ray = .{ .o = .{ -2.0, 0.0, 0.0 }, .d = .{ 1.0, 0.0, 0.0 } };
    const size: Vec3 = .{ 0.5, 0.5, 0.5 };
    if (intersectRayBox(ray, size)) |result| {
        try std.testing.expectApproxEqAbs(1.5, result.dist, 4 * math.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm[0], 4 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm[1], 4 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm[2], 4 * math.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRayBox ray origin inside box" {
    const ray: Ray = .{ .o = .{ 0.25, 0.0, 0.0 }, .d = .{ 1.0, 0.0, 0.0 } };
    const size: Vec3 = .{ 0.5, 0.5, 0.5 };
    if (intersectRayBox(ray, size)) |result| {
        try std.testing.expectApproxEqAbs(0.25, result.dist, 4 * math.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm[0], 4 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm[1], 4 * math.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm[2], 4 * math.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRayBox box behind ray origin" {
    const ray: Ray = .{ .o = .{ 0.75, 0.0, 0.0 }, .d = .{ 1.0, 0.0, 0.0 } };
    const size: Vec3 = .{ 0.5, 0.5, 0.5 };
    if (intersectRayBox(ray, size)) |_| {
        try std.testing.expect(false);
    } else {
        try std.testing.expect(true);
    }
}

/// Variant of Moller-Trumbore ray-triangle intersection adapted from Inigo Quilez at:
///   https://iquilezles.org/articles/intersectors/ and
///   https://www.shadertoy.com/view/MlGcDz
/// This variant saves computation relative to a vanilla application of Cramer's rule by
/// pre-computing some shared terms between determinants.
pub fn intersectRayTriangle(ray: Ray, tri: Triangle) ?IntersectResult {
    const v0v1: Vec3 = sub(tri.vertices[1], tri.vertices[0]);
    const v0v2: Vec3 = sub(tri.vertices[2], tri.vertices[0]);
    const n: Vec3 = cross(v0v1, v0v2);
    const rddn: f32 = dot(ray.d, n);
    if (rddn == 0.0) return null;
    const v0ro: Vec3 = sub(ray.o, tri.vertices[0]);
    const q: Vec3 = cross(v0ro, ray.d);
    const d: f32 = 1.0 / rddn;
    const u: f32 = d * dot(mul(-1.0, q), v0v2);
    const v: f32 = d * dot(q, v0v1);
    const t: f32 = d * dot(mul(-1.0, n), v0ro);
    if (u < 0.0 or v < 0.0 or (u + v) > 1.0 or t < 0.0) return null;
    const nn: Vec3 = normalize(n);
    return .{ .dist = t, .norm = if (dot(n, ray.d) < 0.0) nn else mul(-1.0, nn) };
}

const test_tri_flat = Triangle{ .vertices = .{
    .{ 0.0, 0.0, 0.0 },
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
} };

const test_tri_tilt = Triangle{ .vertices = .{
    .{ 1.0, 0.0, 0.0 },
    .{ 0.0, 1.0, 0.0 },
    .{ 0.0, 0.0, 1.0 },
} };

test "intersectRayTriangle parallel" {
    const ray: Ray = .{ .o = .{ 0.1, 0.1, 0.1 }, .d = .{ 1.0, 0.0, 0.0 } };
    try std.testing.expectEqual(null, intersectRayTriangle(ray, test_tri_flat));
}

test "intersectRayTriangle coplanar" {
    const ray: Ray = .{ .o = .{ -0.1, 0.1, 0.0 }, .d = .{ 1.0, 0.0, 0.0 } };
    try std.testing.expectEqual(null, intersectRayTriangle(ray, test_tri_flat));
}

test "intersectRayTriangle low side angled hit" {
    const ray: Ray = .{ .o = .{ -2.0, 1.0 / 3.0, 1.0 / 3.0 }, .d = .{ 1.0, 0.0, 0.0 } };
    const result = intersectRayTriangle(ray, test_tri_tilt) orelse unreachable;
    try std.testing.expectApproxEqAbs(7.0 / 3.0, result.dist, 4 * math.eps);
    try std.testing.expectApproxEqAbs(-1.0 / @sqrt(3.0), result.norm[0], 4 * math.eps);
    try std.testing.expectApproxEqAbs(-1.0 / @sqrt(3.0), result.norm[1], 4 * math.eps);
    try std.testing.expectApproxEqAbs(-1.0 / @sqrt(3.0), result.norm[2], 4 * math.eps);
}

test "intersectRayTriangle high side angled hit" {
    const ray: Ray = .{ .o = .{ 7.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0 }, .d = .{ -1.0, 0.0, 0.0 } };
    const result = intersectRayTriangle(ray, test_tri_tilt) orelse unreachable;
    try std.testing.expectApproxEqAbs(2.0, result.dist, 4 * math.eps);
    try std.testing.expectApproxEqAbs(1.0 / @sqrt(3.0), result.norm[0], 4 * math.eps);
    try std.testing.expectApproxEqAbs(1.0 / @sqrt(3.0), result.norm[1], 4 * math.eps);
    try std.testing.expectApproxEqAbs(1.0 / @sqrt(3.0), result.norm[2], 4 * math.eps);
}

test "intersectRayTriangle miss with u < 0" {
    const ray: Ray = .{ .o = .{ 0.0, -0.1, 0.0 }, .d = .{ 1.0, 0.0, 1.0 } };
    try std.testing.expectEqual(null, intersectRayTriangle(ray, test_tri_tilt));
}

test "intersectRayTriangle miss with v < 0" {
    const ray: Ray = .{ .o = .{ 0.0, 0.0, -0.1 }, .d = .{ 1.0, 1.0, 0.0 } };
    try std.testing.expectEqual(null, intersectRayTriangle(ray, test_tri_tilt));
}

test "intersectRayTriangle miss with u + v > 1" {
    const ray: Ray = .{ .o = .{ -0.1, 0.0, 0.0 }, .d = .{ 0.0, 1.0, 1.0 } };
    try std.testing.expectEqual(null, intersectRayTriangle(ray, test_tri_tilt));
}

test "intersectRayTriangle behind ray origin" {
    const ray: Ray = .{
        .o = add(@as(Vec3, @splat(1.0 / 3.0)), @as(Vec3, @splat(0.1))),
        .d = .{ 1.0, 1.0, 1.0 },
    };
    try std.testing.expectEqual(null, intersectRayTriangle(ray, test_tri_tilt));
}
