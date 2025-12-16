const std = @import("std");

const m = @import("math.zig");

pub const Ray = struct {
    o: m.Vec3,
    d: m.Vec3,
};

pub const Sphere = struct {
    r: f32,
};

pub const Box = struct {
    size: m.Vec3,
};

const IntersectResultRayGeom = struct {
    dist: f32 = 0.0,
    norm: m.Vec3 = .{},
};

fn intersectRaySphere(ray: Ray, sphere: Sphere) ?IntersectResultRayGeom {
    const roh: f32 = m.dot(ray.o, ray.d); // ray origin to half-chord dist
    const woc: m.Vec3 = m.sub(ray.o, m.mul(roh, ray.d)); // world origin to chord vec
    const hsq: f32 = sphere.r * sphere.r - m.dot(woc, woc);
    // closest ray point is outside sphere
    if (hsq < 0.0) return null;
    const seh: f32 = @sqrt(hsq); // sphere edge to half-chord distance
    const tn: f32 = -roh - seh; // near
    const tf: f32 = -roh + seh; // far
    // sphere is behind ray origin
    if (tf < 0.0) return null;
    // ray origin is inside sphere
    if (tn < 0.0) {
        return IntersectResultRayGeom{
            .dist = tf,
            .norm = m.mul(m.mul(-1.0, m.add(ray.o, m.mul(ray.d, tf))), m.sdiv(1.0, sphere.r)),
        };
    }
    // sphere is ahead of ray origin
    return IntersectResultRayGeom{
        .dist = tn, // note normalization below is simple since the vector has magnitude radius
        .norm = m.mul(m.add(ray.o, m.mul(ray.d, tn)), m.sdiv(1.0, sphere.r)),
    };
}

// fn intersectRayBox(ray: Ray, box: Box) ?IntersectResultRayGeom {
//
// }

pub const GeometryType = union(enum) {
    sphere: Sphere,
};

pub const Material = enum { diffuse, specular };

pub const Object = struct {
    geom: GeometryType = undefined,
    itfm: m.Mat4 = .{},
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

pub fn intersectRayObject(wray: Ray, obj: Object) ?IntersectResult {
    const mray: Ray = .{
        .o = m.toVec3(m.matvec4(obj.itfm, m.toHomogeneousPos(wray.o))),
        .d = m.toVec3(m.matvec4(obj.itfm, m.toHomogeneousDir(wray.d))),
    };

    const intersect_geom: ?IntersectResultRayGeom = switch (obj.geom) {
        .sphere => |geom_sphere| intersectRaySphere(mray, geom_sphere),
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

test "intersectRaySphere --- sphere ahead" {
    const ray: Ray = .{ .o = .{ .data = .{ -2.0, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const sphere: Sphere = .{ .r = 1.0 };
    if (intersectRaySphere(ray, sphere)) |result| {
        try std.testing.expectApproxEqAbs(1.0, result.dist, 4 * m.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm.data[0], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[1], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[2], 4 * m.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRaySphere --- ray origin inside sphere" {
    const ray: Ray = .{ .o = .{ .data = .{ -0.5, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const sphere: Sphere = .{ .r = 1.0 };
    if (intersectRaySphere(ray, sphere)) |result| {
        try std.testing.expectApproxEqAbs(1.5, result.dist, 4 * m.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm.data[0], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[1], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[2], 4 * m.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRaySphere --- sphere behind ray origin" {
    const ray: Ray = .{ .o = .{ .data = .{ 1.5, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const sphere: Sphere = .{ .r = 1.0 };
    if (intersectRaySphere(ray, sphere)) |_| {
        try std.testing.expect(false);
    } else {
        try std.testing.expect(true);
    }
}
