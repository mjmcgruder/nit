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

pub const Triangle = struct {
    vertices: [3]m.Vec3,
};

pub const Mesh = struct {
    vrt: std.ArrayList(m.Vec3) = .empty,
    ind: std.ArrayList(u32) = .empty,

    pub fn deinit(self: *Mesh, allocator: std.mem.Allocator) void {
        self.vrt.deinit(allocator);
        self.ind.deinit(allocator);
    }
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

fn intersectRayBox(ray: Ray, box: Box) ?IntersectResultRayGeom {
    const ird: m.Vec3 = m.div(1.0, ray.d); // invserse ray direction
    const dt0: m.Vec3 = m.mul(ird, ray.o); // parametric distance to axis-orthogonal plane at 0
    const bdc: m.Vec3 = m.mul(m.abs(ird), box.size); // box distance correction
    const atn: m.Vec3 = m.sub(m.mul(-1.0, dt0), bdc);
    const atf: m.Vec3 = m.add(m.mul(-1.0, dt0), bdc);
    const tn: f32 = @max(atn.data[0], atn.data[1], atn.data[2]);
    const tf: f32 = @min(atf.data[0], atf.data[1], atf.data[2]);
    // miss or box behind ray origin
    if (tn > tf or tf < 0.0) return null;
    // hit with box ahead of ray origin
    if (tn > 0.0) {
        return .{
            .dist = tn,
            .norm = m.mul(m.step(tn, atn), m.mul(-1.0, m.sign(ray.d))), // TODO: normalization occasionally slightly incorrect due to FP
        };
    }
    // hit with box ahead of ray origin
    else {
        return .{
            .dist = tf,
            .norm = m.mul(m.step(atf, tf), m.mul(-1.0, m.sign(ray.d))),
        };
    }
}

fn intersectRayTriangle(ray: Ray, tri: Triangle) ?IntersectResultRayGeom {
    const v0v1: m.Vec3 = m.sub(tri.vertices[1], tri.vertices[0]);
    const v0v2: m.Vec3 = m.sub(tri.vertices[2], tri.vertices[0]);
    const v0ro: m.Vec3 = m.sub(ray.o, tri.vertices[0]);
    const n: m.Vec3 = m.cross(v0v1, v0v2);
    const q: m.Vec3 = m.cross(v0ro, ray.d);
    const d: f32 = 1.0 / m.dot(ray.d, n);
    const u: f32 = d * m.dot(m.mul(-1.0, q), v0v2);
    const v: f32 = d * m.dot(q, v0v1);
    const t: f32 = d * m.dot(m.mul(-1.0, n), v0ro);
    if (u < 0.0 or v < 0.0 or (u + v) > 1.0 or t < 0.0) return null;
    const nn: m.Vec3 = m.normalize(n);
    return .{ .dist = t, .norm = if (m.dot(n, ray.d) < 0.0) nn else m.mul(-1.0, nn) };
}

fn intersectRayMesh(ray: Ray, mesh: Mesh) ?IntersectResultRayGeom {
    var result: IntersectResultRayGeom = .{ .dist = std.math.floatMax(f32), .norm = undefined };
    std.debug.assert(mesh.ind.items.len % 3 == 0);
    const ntri: usize = mesh.ind.items.len / 3;
    var it: usize = 0;
    while (it < ntri) : (it += 1) {
        const triangle: Triangle = .{ .vertices = .{
            mesh.vrt.items[mesh.ind.items[3 * it + 0]],
            mesh.vrt.items[mesh.ind.items[3 * it + 1]],
            mesh.vrt.items[mesh.ind.items[3 * it + 2]],
        } };
        if (intersectRayTriangle(ray, triangle)) |intersect| {
            if (intersect.dist < result.dist) {
                result = intersect;
            }
        }
    }
    return if (result.dist == std.math.floatMax(f32)) null else result;
}

pub const GeometryType = union(enum) {
    sphere: Sphere,
    box: Box,
    triangle: Triangle,
    mesh: Mesh,
};

pub const Material = enum { diffuse, specular };

pub const Object = struct {
    geom: GeometryType = undefined,
    trfm: m.Mat4 = .{},
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
    const itfm: m.Mat4 = m.invertTransform(obj.trfm);

    const mray: Ray = .{
        .o = m.toVec3(m.matvec4(itfm, m.toHomogeneousPos(wray.o))),
        .d = m.toVec3(m.matvec4(itfm, m.toHomogeneousDir(wray.d))),
    };

    var intersect_geom: ?IntersectResultRayGeom = switch (obj.geom) {
        .sphere => |geom_sphere| intersectRaySphere(mray, geom_sphere),
        .box => |geom_box| intersectRayBox(mray, geom_box),
        .triangle => |geom_triangle| intersectRayTriangle(mray, geom_triangle),
        .mesh => |geom_mesh| intersectRayMesh(mray, geom_mesh),
    };

    if (intersect_geom) |*geom_result| {
        geom_result.norm = m.toVec3(
            m.matvec4(obj.trfm, m.toHomogeneousDir(geom_result.norm)),
        );
        return IntersectResult{
            .geom = geom_result.*,
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

test "intersectRayBox --- box ahead" {
    const ray: Ray = .{ .o = .{ .data = .{ -2.0, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const box: Box = .{ .size = .{ .data = .{ 0.5, 0.5, 0.5 } } };
    if (intersectRayBox(ray, box)) |result| {
        try std.testing.expectApproxEqAbs(1.5, result.dist, 4 * m.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm.data[0], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[1], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[2], 4 * m.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRayBox --- ray origin inside box" {
    const ray: Ray = .{ .o = .{ .data = .{ 0.25, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const box: Box = .{ .size = .{ .data = .{ 0.5, 0.5, 0.5 } } };
    if (intersectRayBox(ray, box)) |result| {
        try std.testing.expectApproxEqAbs(0.25, result.dist, 4 * m.eps);
        try std.testing.expectApproxEqAbs(-1.0, result.norm.data[0], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[1], 4 * m.eps);
        try std.testing.expectApproxEqAbs(0.0, result.norm.data[2], 4 * m.eps);
    } else {
        try std.testing.expect(false);
    }
}

test "intersectRayBox --- box behind ray origin" {
    const ray: Ray = .{ .o = .{ .data = .{ 0.75, 0.0, 0.0 } }, .d = .{ .data = .{ 1.0, 0.0, 0.0 } } };
    const box: Box = .{ .size = .{ .data = .{ 0.5, 0.5, 0.5 } } };
    if (intersectRayBox(ray, box)) |_| {
        try std.testing.expect(false);
    } else {
        try std.testing.expect(true);
    }
}
