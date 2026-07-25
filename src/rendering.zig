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

pub const Renderers = enum {
    depth,
    backward_path_tracing,
};

pub fn renderDepth(camera_ray: prim.Ray, scene: []const geom.Object) Vec3 {
    const far = geom.IntersectResult{ .geom = .{ .dist = std.math.floatMax(f32) } };
    const d: f32 = (geom.intersectScene(camera_ray, scene) orelse far).geom.dist;
    return @splat(1.0 / (d + 1.0));
}

pub fn renderWithBackwardPathTracing(
    camera_ray: prim.Ray,
    scene: []const geom.Object,
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
                ro = add(add(ro, mul(rd, dist)), mul(norm, 1e-5));
                switch (intersect.mtrl) {
                    geom.Material.diffuse => {
                        const sample: samp.BRDFSample = samp.sampleLambertianBRDF(norm, rng);
                        bounce_stack[stack_i] = BounceNode{
                            .brdf = mul(intersect.refl, 1.0 / std.math.pi),
                            .emit = intersect.emit,
                            .c_th = sample.p * std.math.pi,
                            .prob = sample.p,
                        };
                        rd = sample.dir;
                    },
                    geom.Material.specular => {
                        const sample: samp.BRDFSample = samp.sampleSpecularBRDF(norm, mul(rd, -1.0));
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
