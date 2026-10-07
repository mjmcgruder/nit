const std = @import("std");

const math = @import("math.zig");
const prim = @import("geometry_primitives.zig");
const geom = @import("geometry.zig");
const samp = @import("sampling.zig");
const rand = @import("random.zig");

const Vec3 = math.Vec3;
const mul = math.mul;
const add = math.add;
const sub = math.sub;
const dot = math.dot;
const div = math.div;
const normalize = math.normalize;

pub const Renderers = enum {
    depth,
    direct_lighting,
    path_tracing,
};

const bump = 1.0e-5;

pub fn renderDepth(camera_ray: prim.Ray, scene: geom.Scene) Vec3 {
    const far = geom.IntersectResult{ .geom = .{ .dist = std.math.floatMax(f32) } };
    const d: f32 = (geom.intersectScene(camera_ray, scene) orelse far).geom.dist;
    return @splat(1.0 / (d + 1.0));
}

fn computeBRDF(wi: Vec3, wr: Vec3, surf: geom.IntersectResult) Vec3 {
    const n: Vec3 = surf.geom.norm;
    return switch (surf.mtrl) {
        geom.Material.diffuse => mul(surf.refl, 1.0 / std.math.pi),
        geom.Material.specular => specular_brdf: {
            const expected_refl = normalize(sub(mul(2.0, mul(dot(n, wi), n)), wi));
            if (@abs(1.0 - dot(expected_refl, wr)) < 16.0 * math.eps) {
                break :specular_brdf mul(surf.refl, math.sdiv(1.0, dot(wi, n)));
            } else {
                break :specular_brdf @splat(0.0);
            }
        },
    };
}

/// NOTE: This visibility operator assumes you're not sampling the back side of lights. If you are,
/// the sample probability density of the sample will be off by a factor of two.
fn checkVisibility(light: geom.Object, scene: geom.Scene, wi: prim.Ray) bool {
    const res_light = geom.intersectScene(wi, .{ .objects = &.{light} }) orelse return false;
    const res_scene = geom.intersectScene(wi, scene) orelse return false;
    if (res_light.geom.dist == res_scene.geom.dist) return true else return false;
}

fn estimateRadianceFromLights(
    scene: geom.Scene,
    surf: geom.IntersectResult,
    orig: Vec3,
    wr: Vec3,
    rng: *rand.PCGHash,
) ?Vec3 {
    const sample: samp.Sample, const light: geom.Object =
        samp.sampleLights(orig, scene, rng) orelse return null;
    std.debug.assert(std.math.approxEqAbs(f32, math.mag(sample.dir), 1.0, 4.0 * math.eps));

    const cos_theta: f32 = dot(sample.dir, surf.geom.norm);

    if (cos_theta <= 0.0 or !checkVisibility(light, scene, .{ .o = orig, .d = sample.dir }))
        return null;

    const brdf: Vec3 = computeBRDF(sample.dir, wr, surf);
    const f = mul(brdf, mul(light.emit, cos_theta));
    return mul(f, math.sdiv(1.0, sample.p));
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
        const wr: Vec3 = mul(-1.0, camera_ray.d);
        const estimate: Vec3 =
            estimateRadianceFromLights(scene, surf, orig, wr, rng) orelse continue;
        sum = add(sum, estimate);
    }

    return add(div(sum, @as(f32, @floatFromInt(num_samples))), surf.emit);
}

pub fn render(
    camera_ray: prim.Ray,
    scene: geom.Scene,
    num_samples: usize,
    rng: *rand.PCGHash,
) Vec3 {
    const BounceNode = struct {
        oppi: prim.Ray = .{},
        oppr: prim.Ray = .{},
        surf: geom.IntersectResult = .{},
        prob: f32 = 1.0, // prob that wi was selected (remember we're reversed)
    };

    const max_bounces: usize = 1 << 3;
    var bounce_stack: [max_bounces]BounceNode = undefined;
    var stack_i: usize = undefined;

    var sample_i: usize = 0;
    var pixel_color: Vec3 = .{ 0.0, 0.0, 0.0 };
    sample_loop: while (sample_i < num_samples) : (sample_i += 1) {
        stack_i = 0;

        // build bounce stack

        var oppr: prim.Ray = .{ .o = camera_ray.o, .d = camera_ray.d };
        bounce_loop: while (stack_i < max_bounces) : (stack_i += 1) {
            if (geom.intersectScene(oppr, scene)) |intersect| {
                const norm = intersect.geom.norm;
                const sample: samp.Sample = switch (intersect.mtrl) {
                    geom.Material.diffuse => samp.sampleLambertianBRDF(norm, rng),
                    geom.Material.specular => samp.sampleSpecularBRDF(norm, mul(oppr.d, -1.0)),
                };
                const oppi = prim.Ray{
                    .o = add(add(oppr.o, mul(oppr.d, intersect.geom.dist)), mul(norm, bump)),
                    .d = sample.dir,
                };
                bounce_stack[stack_i] = BounceNode{
                    .oppi = oppi,
                    .oppr = oppr,
                    .surf = intersect,
                    .prob = sample.p,
                };
                oppr = oppi;
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
            const wr: Vec3 = mul(node.oppr.d, -1.0);

            const pest: Vec3 = brdf_sample: {
                const wi: Vec3 = node.oppi.d;
                const brdf: Vec3 = computeBRDF(wi, wr, node.surf);
                const cost: f32 = dot(wi, node.surf.geom.norm);
                const f: Vec3 = mul(mul(brdf, incoming), cost);
                break :brdf_sample mul(f, math.sdiv(1.0, node.prob));
            };
            if (math.mag(pest) > 0.0) {
                incoming = add(node.surf.emit, pest);
                continue;
            }

            const lest: Vec3 =
                estimateRadianceFromLights(scene, node.surf, node.oppi.o, wr, rng) orelse @splat(0.0);
            if (math.mag(lest) > 0.0) {
                incoming = add(node.surf.emit, lest);
                continue;
            }

            if (stack_i == 0) { // TODO: line below causes excess noise if always applied... why?
                incoming = add(node.surf.emit, @as(Vec3, @splat(0.0)));
            } else {
                incoming = @splat(0.0);
            }
        }

        // average sample color into pixel color

        pixel_color = add(
            pixel_color,
            mul(incoming, 1.0 / @as(f32, @floatFromInt(num_samples))),
        );
    }

    return pixel_color;
}
