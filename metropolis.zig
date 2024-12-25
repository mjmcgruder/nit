const std = @import("std");

// math library

const Vec3 = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,
};

const unit_x: Vec3 = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 };
const unit_y: Vec3 = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
const unit_z: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 1.0 };

inline fn broadcast(a: anytype) Vec3 {
    if (@TypeOf(a) == Vec3) {
        return a;
    } else if (@TypeOf(a) == comptime_float) {
        return Vec3{ .x = a, .y = a, .z = a };
    } else if (@TypeOf(a) == f64) {
        return Vec3{ .x = a, .y = a, .z = a };
    } else {
        comptime unreachable;
    }
}

inline fn add(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{
        .x = a.x + b.x,
        .y = a.y + b.y,
        .z = a.z + b.z,
    };
}

inline fn sub(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{
        .x = a.x - b.x,
        .y = a.y - b.y,
        .z = a.z - b.z,
    };
}

inline fn mul(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{
        .x = a.x * b.x,
        .y = a.y * b.y,
        .z = a.z * b.z,
    };
}

inline fn div(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{
        .x = a.x / b.x,
        .y = a.y / b.y,
        .z = a.z / b.z,
    };
}

inline fn dot(a: Vec3, b: Vec3) f64 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

inline fn cross(a: Vec3, b: Vec3) Vec3 {
    return Vec3{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

inline fn mag(a: Vec3) f64 {
    return @sqrt(dot(a, a));
}

inline fn normalize(a: Vec3) Vec3 {
    return div(a, mag(a));
}

inline fn clamp(a: f64, comptime min: f64, comptime max: f64) f64 {
    return if (a < min) min else if (a > max) max else a;
}

// geometry definitions

const IntersectResult = struct {
    d: f64, // distance
    n: Vec3, // normal
    c: Vec3, // color
    e: Vec3, // emittance
};

const Object = struct {
    c: Vec3, // center
    r: f64, // radius
    refl: Vec3, // reflectance
    emit: Vec3, // emittance

    pub inline fn intersect(this: Object, ro: Vec3, rd: Vec3) ?IntersectResult {
        const oc: Vec3 = sub(ro, this.c);
        const b: f64 = dot(oc, rd);
        const qc: Vec3 = sub(oc, mul(b, rd));
        const h: f64 = this.r * this.r - dot(qc, qc);
        if (h < 0.0)
            return null;
        const t: f64 = -b - @sqrt(h);
        if (t <= 0.0) // tad clunky, no?
            return null;
        const n: Vec3 = normalize(sub(add(ro, mul(rd, t)), this.c));
        return IntersectResult{ .d = t, .n = n, .c = this.refl, .e = this.emit };
    }
};

const BounceNode = struct {
    brdf: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    emit: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    c_th: f64 = 0.0,
    prob: f64 = 1.0,
};

// quality settings

const max_bounces = 1 << 3;
const num_samples = 1 << 3;

// scene definition

const window_w: usize = 1920; // window width in pixels
const window_h: usize = 1080; // window height in pixels

const camera_position: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }; // camera position
const target_position: Vec3 = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 }; // target position
const up_vector: Vec3 = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 }; // up vector
const fov: f64 = 90.0; // horizontal field of view in degrees

const scene = [_]Object{
    Object{
        .c = Vec3{ .x = 1.0, .y = 0.4, .z = 0.0 },
        .r = 0.1,
        .refl = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .emit = Vec3{ .x = 12.0, .y = 12.0, .z = 12.0 },
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = 0.0, .z = 1000.0 + 0.5 },
        .r = 1000.0,
        .refl = Vec3{ .x = 0.75, .y = 0.0, .z = 0.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    },
    Object{
        .c = Vec3{ .x = 1000.0 + 1.0 + 0.5, .y = 0.0, .z = 0.0 },
        .r = 1000.0,
        .refl = Vec3{ .x = 0.0, .y = 0.75, .z = 0.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = 0.0, .z = -1000.0 - 0.5 },
        .r = 1000.0,
        .refl = Vec3{ .x = 0.0, .y = 0.0, .z = 0.75 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = -1000.0 - 0.5, .z = 0.0 },
        .r = 1000.0,
        .refl = Vec3{ .x = 0.75, .y = 0.75, .z = 0.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = 1000.0 + 0.5, .z = 0.0 },
        .r = 1000.0,
        .refl = Vec3{ .x = 0.0, .y = 0.75, .z = 0.75 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    },
};

// main program

const Pixel = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

fn intersectSceneNaive(ro: Vec3, rd: Vec3) ?IntersectResult {
    var intersect = IntersectResult{
        .d = std.math.floatMax(f64),
        .n = undefined,
        .c = undefined,
        .e = undefined,
    };
    for (&scene) |*object| {
        if (object.intersect(ro, rd)) |result| {
            if (result.d < intersect.d) {
                intersect = result;
            }
        }
    }
    return if (intersect.d == std.math.floatMax(f64)) null else intersect;
}

fn randomRayInHemisphere(n: Vec3, rng: *const std.Random) Vec3 {
    const local_z: Vec3 = n;
    const local_y: Vec3 = normalize(cross(local_z, if (@abs(local_z.x) < 0.9) unit_x else unit_y));
    const local_x: Vec3 = normalize(cross(local_y, local_z));
    const theta: f64 = rng.float(f64) * 2.0 * std.math.pi;
    const u: f64 = rng.float(f64);
    const x: f64 = @sqrt(1.0 - u * u) * @cos(theta);
    const y: f64 = @sqrt(1.0 - u * u) * @sin(theta);
    const z: f64 = u;
    return normalize(add(add(mul(local_x, x), mul(local_y, y)), mul(local_z, z)));
}

fn writeImage(frame_buffer: []const Pixel, file_name: []const u8) !void {
    const file: std.fs.File = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    var buffer_wrapper = std.io.bufferedWriter(file.writer());
    var file_writer = buffer_wrapper.writer();

    try file_writer.print("P3\n", .{});
    try file_writer.print("{d} {d}\n", .{ window_w, window_h });
    try file_writer.print("255\n", .{});
    for (frame_buffer) |pixel| {
        try file_writer.print("{d:>3} {d:>3} {d:>3}\n", .{ pixel.r, pixel.g, pixel.b });
    }

    try buffer_wrapper.flush();
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // initialize image

    const frame_buffer: []Pixel = try allocator.alloc(Pixel, window_w * window_h);
    @memset(frame_buffer, Pixel{});

    // initialize rays

    const window_h_flt: f64 = @floatFromInt(window_h);
    const window_w_flt: f64 = @floatFromInt(window_w);

    const t: Vec3 = normalize(sub(target_position, camera_position)); // target vector
    const b: Vec3 = normalize(cross(t, up_vector)); // horizontal vector
    const v: Vec3 = normalize(cross(b, t)); // vertical vector

    const hw: f64 = @tan(0.5 * fov); // view port half width and height at distance 1
    const hh: f64 = hw * ((window_h_flt - 1.0) / (window_w_flt - 1.0));

    const ul: Vec3 = add(sub(t, mul(hw, b)), mul(hh, v)); // upper left point
    const inc_w: f64 = (2.0 * hw) / (window_w_flt - 1.0);
    const inc_h: f64 = (2.0 * hh) / (window_h_flt - 1.0);

    const rays: []Vec3 = try allocator.alloc(Vec3, window_w * window_h);
    for (rays, 0..) |*item, i| {
        const r: usize = i / window_w;
        const c: usize = i - (window_w * r);
        const r_flt: f64 = @floatFromInt(r);
        const c_flt: f64 = @floatFromInt(c);
        item.* = normalize(add(ul, add(mul(-inc_h * r_flt, v), mul(inc_w * c_flt, b))));
    }

    // render a depth map

    // // find depth map and limits
    // var min_depth: f64 = std.math.floatMax(f64);
    // var max_depth: f64 = -std.math.floatMax(f64);
    // const depths: []f64 = try allocator.alloc(f64, window_w * window_h);
    // @memset(depths, std.math.floatMax(f64));
    // for (rays, depths) |*ray, *depth| {
    //     for (&scene) |*object| {
    //         if (object.geometry.intersect(cp, ray.*)) |result| {
    //             depth.* = @min(depth.*, result.dist);
    //             min_depth = @min(min_depth, result.dist);
    //             max_depth = @max(max_depth, result.dist);
    //         }
    //     }
    // }
    //
    // // write depth map to frame buffer
    // for (frame_buffer, depths) |*pixel, *depth| {
    //     const scale = (depth.* - min_depth) / (max_depth - min_depth);
    //     if (scale < 0.0 or scale > 1.0) continue;
    //     const scale_int: u8 = @intFromFloat(scale * 255.0);
    //     pixel.r = scale_int;
    //     pixel.g = scale_int;
    //     pixel.b = scale_int;
    // }

    // render diffuse reflection

    const num_samples_flt: f64 = @floatFromInt(num_samples);

    var prng = std.rand.DefaultPrng.init(42);
    const rng = prng.random();

    var bounce_stack: [max_bounces]BounceNode = undefined;
    var stack_i: usize = undefined;

    for (rays, frame_buffer) |*initial_ray, *pixel| {
        var sample_i: usize = 0;
        var pixel_color: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        while (sample_i < num_samples) : (sample_i += 1) {
            stack_i = 0;
            // build bounce stack
            var ro: Vec3 = camera_position;
            var rd: Vec3 = initial_ray.*;
            while (stack_i < max_bounces) : (stack_i += 1) {
                if (intersectSceneNaive(ro, rd)) |intersect| {
                    const new_ray: Vec3 = randomRayInHemisphere(intersect.n, &rng);

                    bounce_stack[stack_i] = BounceNode{
                        .brdf = mul(intersect.c, 1.0 / std.math.pi),
                        .emit = intersect.e,
                        .c_th = dot(new_ray, intersect.n),
                        .prob = 1.0 / (2.0 * std.math.pi),
                    };

                    ro = add(ro, mul(rd, intersect.d));
                    rd = new_ray;
                } else {
                    break;
                }
            }
            // accumulate incoming color by unwinding bounce stack
            var incoming: Vec3 = Vec3{}; // start black
            while (stack_i > 0) {
                stack_i -= 1;
                const node: BounceNode = bounce_stack[stack_i];
                incoming = add(
                    node.emit,
                    mul(mul(mul(node.brdf, incoming), node.c_th), 1.0 / node.prob),
                );
            }
            // average sample color into pixel color
            pixel_color = add(pixel_color, mul(incoming, 1.0 / num_samples_flt));
        }
        // set final color value
        pixel_color.x = clamp(pixel_color.x, 0.0, 1.0);
        pixel_color.y = clamp(pixel_color.y, 0.0, 1.0);
        pixel_color.z = clamp(pixel_color.z, 0.0, 1.0);
        pixel.r = @intFromFloat(pixel_color.x * 255.0);
        pixel.g = @intFromFloat(pixel_color.y * 255.0);
        pixel.b = @intFromFloat(pixel_color.z * 255.0);
    }

    try writeImage(frame_buffer, "image.ppm");
}
