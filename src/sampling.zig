const m = @import("math.zig");
const std = @import("std");

pub const PCG = struct {
    state: u32,

    pub inline fn rand_u32(this: *PCG) u32 {
        const state: u32 = this.state;
        this.state = this.state *% 747796405 +% 2891336453;
        const word: u32 = ((state >> (@as(u5, @intCast((state >> 28) + 4)))) ^ state) *% 277803737;
        return (word >> 22) ^ word;
    }

    pub inline fn rand_f32(this: *PCG) f32 {
        const rnd = @as(f32, @floatFromInt(this.rand_u32()));
        const max = @as(f32, @floatFromInt(std.math.maxInt(u32)));
        return rnd / max;
    }
};

pub fn randomRayInHemisphere(n: m.Vec3, rng: *PCG) m.Vec3 {
    const local_z: m.Vec3 = n;
    const local_y: m.Vec3 = m.normalize(
        m.cross(local_z, if (@abs(local_z.x) < 0.9) m.unit_x else m.unit_y),
    );
    const local_x: m.Vec3 = m.normalize(m.cross(local_y, local_z));
    const theta: f32 = rng.rand_f32() * 2.0 * std.math.pi;
    const u: f32 = rng.rand_f32();
    const r: f32 = @sqrt(1.0 - u * u);
    const x: f32 = r * @cos(theta);
    const y: f32 = r * @sin(theta);
    const z: f32 = u;
    return m.normalize(m.add(m.add(m.mul(local_x, x), m.mul(local_y, y)), m.mul(local_z, z)));
}

pub inline fn specularReflection(n: m.Vec3, w: m.Vec3) m.Vec3 {
    return m.normalize(m.sub(m.mul(2.0, m.mul(m.dot(n, w), n)), w));
}
