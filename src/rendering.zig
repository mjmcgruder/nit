const std = @import("std");

const math = @import("math.zig");
const prim = @import("geometry_primitives.zig");
const geom = @import("geometry.zig");
const samp = @import("sampling.zig");
const rand = @import("random.zig");

const Vec3 = math.Vec3;
const mul = math.mul;
const add = math.add;
const dot = math.dot;
const div = math.div;

pub const Renderers = enum {
    depth,
    direct_lighting,
    backward_path_tracing,
};

const bump = 1.0e-5;

pub fn renderDepth(camera_ray: prim.Ray, scene: geom.Scene) Vec3 {
    const far = geom.IntersectResult{ .geom = .{ .dist = std.math.floatMax(f32) } };
    const d: f32 = (geom.intersectScene(camera_ray, scene) orelse far).geom.dist;
    return @splat(1.0 / (d + 1.0));
}

/// NOTE: This visibility operator assumes you're not sampling the back side of lights. If you are,
/// the sample probability density of the sample will be off by a factor of two.
fn checkVisibility(light: geom.Object, scene: geom.Scene, wi: prim.Ray) bool {
    const res_light = geom.intersectScene(wi, .{ .objects = &.{light} }) orelse return false;
    const res_scene = geom.intersectScene(wi, scene) orelse return false;
    if (res_light.geom.dist == res_scene.geom.dist) return true else return false;
}

pub fn renderDirectLighting(
    camera_ray: prim.Ray,
    scene: geom.Scene,
    num_samples: usize,
    rng: *rand.PCGHash,
) Vec3 {
    const surf: geom.IntersectResult =
        geom.intersectScene(camera_ray, scene) orelse return @splat(0.0);

    const norm: Vec3 = surf.geom.norm;
    const orig: Vec3 = add(add(camera_ray.o, mul(camera_ray.d, surf.geom.dist)), mul(norm, bump));

    std.debug.assert(std.math.approxEqAbs(f32, math.mag(norm), 1.0, 4.0 * math.eps));

    var sum: Vec3 = @splat(0.0);
    for (0..num_samples) |_| {
        const sample: samp.Sample, const light: geom.Object =
            samp.sampleLights(orig, scene, rng) orelse continue;
        std.debug.assert(std.math.approxEqAbs(f32, math.mag(sample.dir), 1.0, 4.0 * math.eps));

        const coth: f32 = dot(sample.dir, norm);

        if (coth <= 0.0 or !checkVisibility(light, scene, .{ .o = orig, .d = sample.dir }))
            continue;

        const brdf: Vec3 = switch (surf.mtrl) {
            geom.Material.diffuse => mul(surf.refl, 1.0 / std.math.pi),
            geom.Material.specular => @splat(0.0), // we're not importance sampling reflectance
        };

        const f = mul(brdf, mul(light.emit, coth));
        const estimate = div(f, @as(f32, @floatFromInt(num_samples)) * sample.p);
        sum = add(sum, estimate);
    }

    return add(sum, surf.emit);
}

pub fn renderWithBackwardPathTracing(
    camera_ray: prim.Ray,
    scene: geom.Scene,
    num_samples: usize,
    rng: *rand.PCGHash,
) Vec3 {
    const BounceNode = struct {
        brdf: Vec3 = .{ 0.0, 0.0, 0.0 },
        emit: Vec3 = .{ 0.0, 0.0, 0.0 },
        c_th: f32 = 0.0,
        prob: f32 = 1.0,
    };

    const max_bounces: usize = 1 << 3;
    var bounce_stack: [max_bounces]BounceNode = undefined;
    var stack_i: usize = undefined;

    var sample_i: usize = 0;
    var pixel_color: Vec3 = .{ 0.0, 0.0, 0.0 };
    sample_loop: while (sample_i < num_samples) : (sample_i += 1) {
        stack_i = 0;

        // build bounce stack
        var ro: Vec3 = camera_ray.o;
        var rd: Vec3 = camera_ray.d;
        bounce_loop: while (stack_i < max_bounces) : (stack_i += 1) {
            if (geom.intersectScene(.{ .o = ro, .d = rd }, scene)) |intersect| {
                const dist = intersect.geom.dist;
                const norm = intersect.geom.norm;
                ro = add(add(ro, mul(rd, dist)), mul(norm, bump));
                switch (intersect.mtrl) {
                    geom.Material.diffuse => {
                        const sample: samp.Sample = samp.sampleLambertianBRDF(norm, rng);
                        bounce_stack[stack_i] = BounceNode{
                            .brdf = mul(intersect.refl, 1.0 / std.math.pi),
                            .emit = intersect.emit,
                            .c_th = sample.p * std.math.pi,
                            .prob = sample.p,
                        };
                        rd = sample.dir;
                    },
                    geom.Material.specular => {
                        const sample: samp.Sample = samp.sampleSpecularBRDF(norm, mul(rd, -1.0));
                        bounce_stack[stack_i] = BounceNode{
                            .brdf = mul(intersect.refl, math.sdiv(1.0, dot(sample.dir, norm))),
                            .emit = intersect.emit,
                            .c_th = dot(sample.dir, norm),
                            .prob = sample.p,
                        };
                        rd = sample.dir;
                    },
                }
            } else {
                if (stack_i == 0) {
                    break :sample_loop;
                } else {
                    break :bounce_loop;
                }
            }
        }

        // accumulate incoming color by unwinding bounce stack
        var incoming: Vec3 = .{ 0.0, 0.0, 0.0 }; // start black
        while (stack_i > 0) {
            stack_i -= 1;
            const node: BounceNode = bounce_stack[stack_i];
            incoming = add(
                node.emit,
                mul(mul(mul(node.brdf, incoming), node.c_th), math.sdiv(1.0, node.prob)),
            );
        }

        // average sample color into pixel color
        pixel_color = add(
            pixel_color,
            mul(incoming, 1.0 / @as(f32, @floatFromInt(num_samples))),
        );
    }

    return pixel_color;
}
