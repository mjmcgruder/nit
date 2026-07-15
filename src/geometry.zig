const std = @import("std");

const math = @import("math.zig");
const mesh = @import("geometry_mesh.zig");
const prim = @import("geometry_primitives.zig");

test {
    _ = mesh;
    _ = prim;
}

pub const GeometryType = union(enum) {
    sphere: prim.Sphere,
    box: prim.Box,
    mesh: mesh.Mesh,
};

pub const Material = enum { diffuse, specular };

pub const Object = struct {
    geom: GeometryType = undefined,
    trfm: math.Mat4 = math.makeIdentityTransform(),
    itfm: math.Mat4 = math.makeIdentityTransform(),
    refl: math.Vec3 = .{ 1.0, 1.0, 1.0 },
    emit: math.Vec3 = .{ 0.0, 0.0, 0.0 },
    mtrl: Material = Material.diffuse,
};

pub const IntersectResult = struct {
    geom: prim.IntersectResult = .{},
    refl: math.Vec3 = .{ 0.0, 0.0, 0.0 },
    emit: math.Vec3 = .{ 0.0, 0.0, 0.0 },
    mtrl: Material = Material.diffuse,
};

pub fn intersectRayObject(wray: prim.Ray, obj: Object) ?IntersectResult {
    const mray: prim.Ray = .{
        .o = math.toCartesian(math.matvec4(obj.itfm, math.toProjectivePos(wray.o))),
        .d = math.toCartesian(math.matvec4(obj.itfm, math.toProjectiveDir(wray.d))),
    };

    var intersect_geom: ?prim.IntersectResult = switch (obj.geom) {
        .sphere => |geom_sphere| prim.intersectRaySphere(mray, geom_sphere),
        .box => |geom_box| prim.intersectRayBox(mray, geom_box),
        .mesh => |geom_mesh| mesh.intersectRayMesh(mray, geom_mesh),
    };

    if (intersect_geom) |*geom_result| {
        geom_result.norm = math.normalize( // <- necessary b/c transform could scale normal
            math.toCartesian(math.matvec4(obj.trfm, math.toProjectiveDir(geom_result.norm))),
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
