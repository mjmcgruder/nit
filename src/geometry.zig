const std = @import("std");

const m = @import("math.zig");

pub const Ray = struct {
    org: m.Vec3,
    dir: m.Vec3,
};

pub const Sphere = struct {
    cntr: m.Vec3,
    rdus: f32,
};

const IntersectResultRayGeom = struct {
    dist: f32 = 0.0,
    norm: m.Vec3 = .{},
};

fn intersectRaySphere(ray: Ray, sphere: Sphere) ?IntersectResultRayGeom {
    const oc: m.Vec3 = m.sub(ray.org, sphere.cntr);
    const b: f32 = m.dot(oc, ray.dir);
    const qc: m.Vec3 = m.sub(oc, m.mul(b, ray.dir));
    const h: f32 = sphere.rdus * sphere.rdus - m.dot(qc, qc);
    if (h < 0.0) // closest ray point is outside sphere
        return null;
    const t: f32 = -b - @sqrt(h);
    if (t <= 0.0) // intersection is behind the ray origin
        return null;
    return IntersectResultRayGeom{
        .dist = t,
        .norm = m.normalize(m.sub(m.add(ray.org, m.mul(ray.dir, t)), sphere.cntr)),
    };
}

pub const GeometryType = union(enum) {
    sphere: Sphere,
};

pub const Material = enum { diffuse, specular };

pub const Object = struct {
    geom: GeometryType = undefined,
    refl: m.Vec3 = m.Vec3{ .data = .{ 1.0, 1.0, 1.0 } },
    emit: m.Vec3 = m.Vec3{ .data = .{ 0.0, 0.0, 0.0 } },
    mtrl: Material = Material.diffuse,
};

pub const IntersectResult = struct {
    geom: IntersectResultRayGeom = .{},
    refl: m.Vec3 = .{},
    emit: m.Vec3 = .{},
    mtrl: Material = Material.diffuse,
};

pub fn intersectRayObject(ray: Ray, obj: Object) ?IntersectResult {
    const intersect_geom: ?IntersectResultRayGeom = switch (obj.geom) {
        .sphere => |geom_sphere| intersectRaySphere(ray, geom_sphere),
    };

    if (intersect_geom) |geom_result| {
        return IntersectResult{
            .geom = geom_result,
            .refl = obj.refl,
            .emit = obj.emit,
            .mtrl = obj.mtrl,
        };
    } else {
        return null;
    }
}

// TESTS -----

// test "Object.intersect --- intersection ahead" {
//     const sphere: Object = .{ .cntr = .{ .data = .{ 1.0, 0.0, 0.0 } }, .rdus = 0.1 };
//     const ro: m.Vec3 = .{ .data = .{ 0.0, 0.0, 0.0 } };
//     const rd: m.Vec3 = .{ .data = .{ 1.0, 0.0, 0.0 } };
//     const intersect: IntersectResult = sphere.intersect(ro, rd).?;
//     try std.testing.expectApproxEqAbs(0.9, intersect.dist, 10 * m.eps);
//     try std.testing.expectApproxEqAbs(-1.0, intersect.norm.data[0], 10 * m.eps);
//     try std.testing.expectApproxEqAbs(0.0, intersect.norm.data[1], 10 * m.eps);
//     try std.testing.expectApproxEqAbs(0.0, intersect.norm.data[2], 10 * m.eps);
// }
//
// test "Object.intersect --- intersection behind (miss)" {
//     const sphere: Object = .{ .cntr = .{ .data = .{ 1.0, 0.0, 0.0 } }, .rdus = 0.1 };
//     const ro: m.Vec3 = .{ .data = .{ 0.0, 0.0, 0.0 } };
//     const rd: m.Vec3 = .{ .data = .{ -1.0, 0.0, 0.0 } };
//     const intersect: IntersectResult = sphere.intersect(ro, rd) orelse .{ .dist = 42.0 };
//     try std.testing.expectEqual(42.0, intersect.dist);
// }
