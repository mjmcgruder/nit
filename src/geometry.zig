const mth = @import("math.zig");

pub const Material = enum { diffuse, specular };

pub const IntersectResult = struct {
    d: f32, // distance
    n: mth.Vec3, // normal
    r: mth.Vec3, // reflectance
    e: mth.Vec3, // emittance
    m: Material,
};

pub const Object = struct {
    c: mth.Vec3 = mth.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }, // center
    r: f32 = 1.0, // radius
    refl: mth.Vec3 = mth.Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 }, // reflectance
    emit: mth.Vec3 = mth.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }, // emittance
    mtrl: Material = Material.diffuse, // material

    pub inline fn intersect(this: Object, ro: mth.Vec3, rd: mth.Vec3) ?IntersectResult {
        const oc: mth.Vec3 = mth.sub(ro, this.c);
        const b: f32 = mth.dot(oc, rd);
        const qc: mth.Vec3 = mth.sub(oc, mth.mul(b, rd));
        const h: f32 = this.r * this.r - mth.dot(qc, qc);
        if (h < 0.0)
            return null;
        const t: f32 = -b - @sqrt(h);
        if (t <= 0.0) // tad clunky, no?
            return null;
        const n: mth.Vec3 = mth.normalize(mth.sub(mth.add(ro, mth.mul(rd, t)), this.c));
        return IntersectResult{ .d = t, .n = n, .r = this.refl, .e = this.emit, .m = this.mtrl };
    }
};
