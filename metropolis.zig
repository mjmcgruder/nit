const std = @import("std");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

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

const PCG_rng = struct {
    state: u32,

    pub inline fn rand_u32(this: *PCG_rng) u32 {
        const state: u32 = this.state;
        this.state = this.state *% 747796405 +% 2891336453;
        const word: u32 = ((state >> (@as(u5, @intCast((state >> 28) + 4)))) ^ state) *% 277803737;
        return (word >> 22) ^ word;
    }

    pub inline fn rand_f32(this: *PCG_rng) f32 {
        return @as(f32, @floatFromInt(this.rand_u32())) / @as(f32, @floatFromInt(std.math.maxInt(u32)));
    }
};

// geometry definitions

const Material = enum { diffuse, specular };

const IntersectResult = struct {
    d: f32, // distance
    n: Vec3, // normal
    r: Vec3, // reflectance
    e: Vec3, // emittance
    m: Material,
};

const Object = struct {
    c: Vec3, // center
    r: f32, // radius
    refl: Vec3, // reflectance
    emit: Vec3, // emittance
    mtrl: Material, // material

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
        return IntersectResult{ .d = t, .n = n, .r = this.refl, .e = this.emit, .m = this.mtrl };
    }
};

const BounceNode = struct {
    brdf: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    emit: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    c_th: f32 = 0.0,
    prob: f32 = 1.0,
};

// quality settings

const max_bounces: usize = 1 << 3;
var num_samples: usize = 1 << 10;

// scene definition

const window_w: usize = 1920; // window width in pixels
const window_h: usize = 1080; // window height in pixels

const camera_position: Vec3 = Vec3{ .x = 1.2, .y = -0.1, .z = -0.4 }; // camera position
const target_position: Vec3 = Vec3{ .x = 1.2, .y = -0.1, .z = 0.5 }; // target position
const up_vector: Vec3 = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 }; // up vector
const fov: f32 = 90.0; // horizontal field of view in degrees

const scene = [_]Object{
    Object{
        .c = Vec3{ .x = 0.6, .y = 0.4, .z = 0.0 },
        .r = 0.1,
        .refl = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .emit = Vec3{ .x = 12.0, .y = 12.0, .z = 12.0 },
        .mtrl = Material.diffuse,
    },
    Object{
        .c = Vec3{ .x = 1.2, .y = -0.1, .z = 0.2 },
        .r = 0.2,
        .refl = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.specular,
    },
    Object{
        .c = Vec3{ .x = 1.4, .y = -0.4, .z = -0.4 },
        .r = 0.1,
        .refl = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.specular,
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = -0.4, .z = 0.4 },
        .r = 0.1,
        .refl = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.specular,
    },
    Object{
        .c = Vec3{ .x = 0.5, .y = -0.4, .z = 0.4 },
        .r = 0.1,
        .refl = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.specular,
    },
    Object{
        .c = Vec3{ .x = 1.3, .y = 0.4, .z = 0.4 },
        .r = 0.08,
        .refl = Vec3{ .x = 1.0, .y = 0.8, .z = 0.1 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.diffuse,
    },
    Object{
        .c = Vec3{ .x = 1.4, .y = -0.42, .z = 0.1 },
        .r = 0.08,
        .refl = Vec3{ .x = 0.05, .y = 0.9, .z = 0.9 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.diffuse,
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = -0.38, .z = 0.1 },
        .r = 0.12,
        .refl = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.diffuse,
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = 0.0, .z = 1000.0 + 0.5 },
        .r = 1000.0,
        .refl = Vec3{ .x = 0.8, .y = 0.2, .z = 0.2 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.diffuse,
    },
    Object{
        .c = Vec3{ .x = 1000.0 + 1.0 + 0.5, .y = 0.0, .z = 0.0 },
        .r = 1000.0,
        .refl = Vec3{ .x = 0.8, .y = 0.0, .z = 0.8 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.diffuse,
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = 0.0, .z = -1000.0 - 0.5 },
        .r = 1000.0,
        .refl = Vec3{ .x = 0.2, .y = 0.2, .z = 0.8 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.diffuse,
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = -1000.0 - 0.5, .z = 0.0 },
        .r = 1000.0,
        .refl = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.diffuse,
    },
    Object{
        .c = Vec3{ .x = 1.0, .y = 1000.0 + 0.5, .z = 0.0 },
        .r = 1000.0,
        .refl = Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
        .emit = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
        .mtrl = Material.diffuse,
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
        .r = undefined,
        .e = undefined,
        .m = undefined,
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

fn randomRayInHemisphere(n: Vec3, rng: *PCG_rng) Vec3 {
    const local_z: Vec3 = n;
    const local_y: Vec3 = normalize(cross(local_z, if (@abs(local_z.x) < 0.9) unit_x else unit_y));
    const local_x: Vec3 = normalize(cross(local_y, local_z));
    const theta: f32 = rng.rand_f32() * 2.0 * std.math.pi;
    const u: f32 = rng.rand_f32();
    const r: f32 = @sqrt(1.0 - u * u);
    const x: f32 = r * @cos(theta);
    const y: f32 = r * @sin(theta);
    const z: f32 = u;
    return normalize(add(add(mul(local_x, x), mul(local_y, y)), mul(local_z, z)));
}

fn randomRayInHemisphereMarsaglia(n: Vec3, rng: *PCG_rng) Vec3 {
    const local_z: Vec3 = n;
    const local_y: Vec3 = normalize(cross(local_z, if (@abs(local_z.x) < 0.9) unit_x else unit_y));
    const local_x: Vec3 = normalize(cross(local_y, local_z));
    while (true) {
        const x1: f32 = rng.rand_f32() * 2.0 - 1.0;
        const x2: f32 = rng.rand_f32() * 2.0 - 1.0;
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

var timer: std.time.Timer = undefined;
var last_print_time: u64 = undefined;
var last_print_mutex: std.Thread.Mutex = std.Thread.Mutex{};

const chunk_size: usize = 1 << 11;
var chunk_start: usize = 0;
var chunk_mutex: std.Thread.Mutex = std.Thread.Mutex{};

var finished_pixels: usize = 0;
var finished_pixels_mutex: std.Thread.Mutex = std.Thread.Mutex{};

fn printRenderProgress(current_time: u64, total_pixels: u64) !void {
    if (last_print_mutex.tryLock()) {
        defer last_print_mutex.unlock();
        last_print_time = current_time;
        try stdout.print("\x1b[1K\r", .{});
        try stdout.print(
            "   {d:5.1}% {d:.1}s",
            .{
                @as(f32, @floatFromInt(finished_pixels)) / @as(f32, @floatFromInt(total_pixels)) * 100.0,
                @as(f32, @floatFromInt(current_time)) / 1.0e9,
            },
        );
    }
}

fn dispatchRender(
    rays: []Vec3,
    frame_buffer: []Pixel,
    thread_num: usize,
) !void {
    var rng: PCG_rng = PCG_rng{ .state = @as(u32, @intCast(42 + thread_num)) };
    while (chunk_start < frame_buffer.len) {
        if (chunk_mutex.tryLock()) {
            const chunk_end = @min(chunk_start + chunk_size, frame_buffer.len);
            const chunk_start_current = chunk_start;
            chunk_start = chunk_end;
            chunk_mutex.unlock();
            try renderPixelRange(rays, frame_buffer, &rng, chunk_start_current, chunk_end);
            {
                finished_pixels_mutex.lock();
                defer finished_pixels_mutex.unlock();
                finished_pixels += chunk_end - chunk_start_current;
            }
        }
    }
}

fn renderPixelRange(
    rays: []Vec3,
    frame_buffer: []Pixel,
    rng: *PCG_rng,
    begin_i: usize,
    end_i: usize,
) !void {
    var bounce_stack: [max_bounces]BounceNode = undefined;
    var stack_i: usize = undefined;

    var pixel_i: usize = begin_i;
    while (pixel_i < end_i) : (pixel_i += 1) {

        // occasionally print a progress update

        const current_time = timer.read();
        if (current_time - last_print_time > 100000000) {
            try printRenderProgress(current_time, frame_buffer.len);
        }

        // render

        const initial_ray: *Vec3 = &rays[pixel_i];
        const pixel: *Pixel = &frame_buffer[pixel_i];

        var sample_i: usize = 0;
        var pixel_color: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        while (sample_i < num_samples) : (sample_i += 1) {
            stack_i = 0;

            // build bounce stack
            var ro: Vec3 = camera_position;
            var rd: Vec3 = initial_ray.*;
            while (stack_i < max_bounces) : (stack_i += 1) {
                if (intersectSceneNaive(ro, rd)) |intersect| {
                    var new_ray: Vec3 = undefined;
                    switch (intersect.m) {
                        Material.diffuse => {
                            new_ray = randomRayInHemisphere(intersect.n, rng);
                            bounce_stack[stack_i] = BounceNode{
                                .brdf = mul(intersect.r, 1.0 / std.math.pi),
                                .emit = intersect.e,
                                .c_th = dot(new_ray, intersect.n),
                                .prob = 1.0 / (2.0 * std.math.pi),
                            };
                        },
                        Material.specular => {
                            const wo: Vec3 = mul(rd, -1.0); // source light direction
                            new_ray = normalize(sub(mul(2.0, mul(dot(intersect.n, wo), intersect.n)), wo));
                            const inv_cos_thetar = 1.0 / dot(new_ray, intersect.n);
                            bounce_stack[stack_i] = BounceNode{
                                .brdf = mul(intersect.r, inv_cos_thetar),
                                .emit = intersect.e,
                                .c_th = dot(new_ray, intersect.n),
                                .prob = 1.0,
                            };
                        },
                    }
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
    timer = try std.time.Timer.start();
    last_print_time = 0;

    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    const args = try std.process.argsAlloc(arena);
    defer std.process.argsFree(arena, args); // does this still need a free with an arena?

    if (args.len != 3) {
        try stdout.print("  usage: metropolis <thread_count> <sample_exponent>\n", .{});
        return;
    }

    const thread_count = try std.fmt.parseInt(usize, args[1], 10);
    num_samples = @as(usize, 1) << try std.fmt.parseInt(u6, args[2], 10);

    // initialize image

    const frame_buffer: []Pixel = try arena.alloc(Pixel, window_w * window_h);
    @memset(frame_buffer, Pixel{});

    // initialize rays

    try stdout.print("  initializing rays...\n", .{});

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

    const rays: []Vec3 = try arena.alloc(Vec3, window_w * window_h);
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

    try stdout.print("  rendering...\n", .{});

    const pool = try arena.alloc(std.Thread, thread_count);
    for (pool, 0..) |*thread, thread_num| {
        thread.* = try std.Thread.spawn(.{}, dispatchRender, .{ rays, frame_buffer, thread_num });
    }
    for (pool) |thread| {
        thread.join();
    }
    try printRenderProgress(timer.read(), frame_buffer.len); // ensure 100% update is printed

    try stdout.print("\n  writing image...\n", .{});

    try writeImage(frame_buffer, "image.ppm");
}
