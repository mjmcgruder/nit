const std = @import("std");

// math library

const Vec3 = struct {
    x: f32 = 0.0,
    y: f32 = 0.0,
    z: f32 = 0.0,
};

const unit_x: Vec3 = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 };
const unit_y: Vec3 = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 };
const unit_z: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 1.0 };

inline fn broadcast(a: anytype) Vec3 {
    if (@TypeOf(a) == Vec3) {
        return a;
    } else if (@TypeOf(a) == comptime_float) {
        return Vec3{ .x = a, .y = a, .z = a };
    } else if (@TypeOf(a) == f32) {
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

inline fn dot(a: Vec3, b: Vec3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

inline fn cross(a: Vec3, b: Vec3) Vec3 {
    return Vec3{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

inline fn mag(a: Vec3) f32 {
    return @sqrt(dot(a, a));
}

inline fn normalize(a: Vec3) Vec3 {
    return div(a, mag(a));
}

inline fn clamp(a: f32, comptime min: f32, comptime max: f32) f32 {
    return if (a < min) min else if (a > max) max else a;
}

// random number generation

var rng_state: u32 = 42;
fn rand_pcg() u32 {
    const state: u32 = rng_state;
    rng_state = rng_state *% 747796405 +% 2891336453;
    const word: u32 = ((state >> (@as(u5, @intCast((state >> 28) + 4)))) ^ state) *% 277803737;
    return (word >> 22) ^ word;
}

fn rand_float() f32 {
    return @as(f32, @floatFromInt(rand_pcg())) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
}

// geometry definitions

const IntersectResult = struct {
    d: f32, // distance
    n: Vec3, // normal
    c: Vec3, // color
    e: Vec3, // emittance
};

const Object = struct {
    c: Vec3, // center
    r: f32, // radius
    refl: Vec3, // reflectance
    emit: Vec3, // emittance

    pub inline fn intersect(this: Object, ro: Vec3, rd: Vec3) ?IntersectResult {
        const oc: Vec3 = sub(ro, this.c);
        const b: f32 = dot(oc, rd);
        const qc: Vec3 = sub(oc, mul(b, rd));
        const h: f32 = this.r * this.r - dot(qc, qc);
        if (h < 0.0)
            return null;
        const t: f32 = -b - @sqrt(h);
        if (t <= 0.0) // tad clunky, no?
            return null;
        const n: Vec3 = normalize(sub(add(ro, mul(rd, t)), this.c));
        return IntersectResult{ .d = t, .n = n, .c = this.refl, .e = this.emit };
    }
};

const BounceNode = struct {
    brdf: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    emit: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    c_th: f32 = 0.0,
    prob: f32 = 1.0,
};

// quality settings

const max_bounces = 1 << 3;
const num_samples = 1 << 13;

// scene definition

const window_w: usize = 1920; // window width in pixels
const window_h: usize = 1080; // window height in pixels

const camera_position: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }; // camera position
const target_position: Vec3 = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 }; // target position
const up_vector: Vec3 = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 }; // up vector
const fov: f32 = 90.0; // horizontal field of view in degrees

const scene = [_]Object{
    Object{
        .c = Vec3{ .x = 1.0, .y = 0.3, .z = -0.3 },
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
        .d = std.math.floatMax(f32),
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
    return if (intersect.d == std.math.floatMax(f32)) null else intersect;
}

fn randomRayInHemisphere(n: Vec3) Vec3 {
    const local_z: Vec3 = n;
    const local_y: Vec3 = normalize(cross(local_z, if (@abs(local_z.x) < 0.9) unit_x else unit_y));
    const local_x: Vec3 = normalize(cross(local_y, local_z));
    const theta: f32 = rand_float() * 2.0 * std.math.pi;
    const u: f32 = rand_float();
    const r: f32 = @sqrt(1.0 - u * u);
    const x: f32 = r * @cos(theta);
    const y: f32 = r * @sin(theta);
    const z: f32 = u;
    return normalize(add(add(mul(local_x, x), mul(local_y, y)), mul(local_z, z)));
}

fn randomRayInHemisphereMarsaglia(n: Vec3) Vec3 {
    const local_z: Vec3 = n;
    const local_y: Vec3 = normalize(cross(local_z, if (@abs(local_z.x) < 0.9) unit_x else unit_y));
    const local_x: Vec3 = normalize(cross(local_y, local_z));
    while (true) {
        const x1: f32 = rand_float() * 2.0 - 1.0;
        const x2: f32 = rand_float() * 2.0 - 1.0;
        const xs: f32 = x1 * x1 + x2 * x2;
        if (xs >= 1.0) continue;
        const rt: f32 = @sqrt(1.0 - xs);
        const x: f32 = 2.0 * x1 * rt;
        const y: f32 = 2.0 * x2 * rt;
        var z: f32 = 1.0 - 2.0 * xs;
        if (z < 0.0) z = -z;
        return normalize(add(add(mul(local_x, x), mul(local_y, y)), mul(local_z, z)));
    }
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
    var print_buff: [2048]u8 = undefined;
    var print_segment: []u8 = undefined;
    var last_print_time: u64 = 0;
    var timer = try std.time.Timer.start();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // initialize image

    const frame_buffer: []Pixel = try allocator.alloc(Pixel, window_w * window_h);
    @memset(frame_buffer, Pixel{});

    // initialize rays

    print_segment = try std.fmt.bufPrint(&print_buff, "  initializing rays...\n", .{});
    _ = try std.posix.write(std.posix.STDOUT_FILENO, print_segment);

    const window_h_flt: f32 = @floatFromInt(window_h);
    const window_w_flt: f32 = @floatFromInt(window_w);

    const t: Vec3 = normalize(sub(target_position, camera_position)); // target vector
    const b: Vec3 = normalize(cross(t, up_vector)); // horizontal vector
    const v: Vec3 = normalize(cross(b, t)); // vertical vector

    const hw: f32 = @tan(0.5 * fov); // view port half width and height at distance 1
    const hh: f32 = hw * ((window_h_flt - 1.0) / (window_w_flt - 1.0));

    const ul: Vec3 = add(sub(t, mul(hw, b)), mul(hh, v)); // upper left point
    const inc_w: f32 = (2.0 * hw) / (window_w_flt - 1.0);
    const inc_h: f32 = (2.0 * hh) / (window_h_flt - 1.0);

    const rays: []Vec3 = try allocator.alloc(Vec3, window_w * window_h);
    for (rays, 0..) |*item, i| {
        const r: usize = i / window_w;
        const c: usize = i - (window_w * r);
        const r_flt: f32 = @floatFromInt(r);
        const c_flt: f32 = @floatFromInt(c);
        item.* = normalize(add(ul, add(mul(-inc_h * r_flt, v), mul(inc_w * c_flt, b))));
    }

    // render a depth map

    // // find depth map and limits
    // var min_depth: f32 = std.math.floatMax(f32);
    // var max_depth: f32 = -std.math.floatMax(f32);
    // const depths: []f32 = try allocator.alloc(f32, window_w * window_h);
    // @memset(depths, std.math.floatMax(f32));
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

    print_segment = try std.fmt.bufPrint(&print_buff, "  rendering...\n", .{});
    _ = try std.posix.write(std.posix.STDOUT_FILENO, print_segment);

    var bounce_stack: [max_bounces]BounceNode = undefined;
    var stack_i: usize = undefined;

    for (rays, frame_buffer, 0..) |*initial_ray, *pixel, pixel_i| {
        const current_time = timer.read();
        if ((current_time - last_print_time > 100000000) or (pixel_i == frame_buffer.len - 1)) {
            last_print_time = current_time;
            _ = try std.posix.write(std.posix.STDOUT_FILENO, "\x1b[1K\r"); // clear line, reset cursor
            print_segment = try std.fmt.bufPrint(
                &print_buff,
                "   {d:5.1}% {d:.1}s",
                .{
                    @as(f32, @floatFromInt(pixel_i)) / @as(f32, @floatFromInt(frame_buffer.len)) * 100.0,
                    @as(f32, @floatFromInt(current_time)) / 1.0e9,
                },
            );
            _ = try std.posix.write(std.posix.STDOUT_FILENO, print_segment);
        }

        var sample_i: usize = 0;
        var pixel_color: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        while (sample_i < num_samples) : (sample_i += 1) {
            stack_i = 0;
            // build bounce stack
            var ro: Vec3 = camera_position;
            var rd: Vec3 = initial_ray.*;
            while (stack_i < max_bounces) : (stack_i += 1) {
                if (intersectSceneNaive(ro, rd)) |intersect| {
                    const new_ray: Vec3 = randomRayInHemisphere(intersect.n);

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
            pixel_color = add(
                pixel_color,
                mul(incoming, 1.0 / @as(f32, @floatFromInt(num_samples))),
            );
        }
        // set final color value
        pixel_color.x = clamp(pixel_color.x, 0.0, 1.0);
        pixel_color.y = clamp(pixel_color.y, 0.0, 1.0);
        pixel_color.z = clamp(pixel_color.z, 0.0, 1.0);
        pixel.r = @intFromFloat(pixel_color.x * 255.0);
        pixel.g = @intFromFloat(pixel_color.y * 255.0);
        pixel.b = @intFromFloat(pixel_color.z * 255.0);
    }

    print_segment = try std.fmt.bufPrint(&print_buff, "\n  writing image...\n", .{});
    _ = try std.posix.write(std.posix.STDOUT_FILENO, print_segment);

    try writeImage(frame_buffer, "image.ppm");
}
