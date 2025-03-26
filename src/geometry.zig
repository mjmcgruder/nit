const std = @import("std");

const mm = @import("math.zig");

pub const Material = enum { diffuse, specular };

pub const IntersectResult = struct {
    dist: f32 = 0.0,
    norm: mm.Vec3 = .{},
    refl: mm.Vec3 = .{},
    emit: mm.Vec3 = .{},
    mtrl: Material = Material.diffuse,
};

pub const Object = struct {
    cntr: mm.Vec3 = mm.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    rdus: f32 = 1.0,
    refl: mm.Vec3 = mm.Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
    emit: mm.Vec3 = mm.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    mtrl: Material = Material.diffuse,

    pub inline fn intersect(this: Object, ro: mm.Vec3, rd: mm.Vec3) ?IntersectResult {
        const oc: mm.Vec3 = mm.sub(ro, this.cntr);
        const b: f32 = mm.dot(oc, rd);
        const qc: mm.Vec3 = mm.sub(oc, mm.mul(b, rd));
        const h: f32 = this.rdus * this.rdus - mm.dot(qc, qc);
        if (h < 0.0) // closest ray point is outside sphere
            return null;
        const t: f32 = -b - @sqrt(h);
        if (t <= 0.0) // intersection is behind the ray origin
            return null;
        return IntersectResult{
            .dist = t,
            .norm = mm.normalize(mm.sub(mm.add(ro, mm.mul(rd, t)), this.cntr)),
            .refl = this.refl,
            .emit = this.emit,
            .mtrl = this.mtrl,
        };
    }
};

// TESTS -----

test "Object.intersect --- intersection ahead" {
    const sphere: Object = .{ .cntr = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .rdus = 0.1 };
    const ro: mm.Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const rd: mm.Vec3 = .{ .x = 1.0, .y = 0.0, .z = 0.0 };
    const intersect: IntersectResult = sphere.intersect(ro, rd).?;
    try std.testing.expectApproxEqAbs(0.9, intersect.dist, 10 * mm.eps);
    try std.testing.expectApproxEqAbs(-1.0, intersect.norm.x, 10 * mm.eps);
    try std.testing.expectApproxEqAbs(0.0, intersect.norm.y, 10 * mm.eps);
    try std.testing.expectApproxEqAbs(0.0, intersect.norm.z, 10 * mm.eps);
}

test "Object.intersect --- intersection behind (miss)" {
    const sphere: Object = .{ .cntr = .{ .x = 1.0, .y = 0.0, .z = 0.0 }, .rdus = 0.1 };
    const ro: mm.Vec3 = .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const rd: mm.Vec3 = .{ .x = -1.0, .y = 0.0, .z = 0.0 };
    const intersect: IntersectResult = sphere.intersect(ro, rd) orelse .{ .dist = 42.0 };
    try std.testing.expectEqual(42.0, intersect.dist);
}
