const std = @import("std");

// math library

const Vec3 = struct {
    x: f64 = 0.0,
    y: f64 = 0.0,
    z: f64 = 0.0,
};

fn broadcast(a: anytype) Vec3 {
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

fn add(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
}

fn sub(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

fn mul(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
}

fn div(a_in: anytype, b_in: anytype) Vec3 {
    const a: Vec3 = broadcast(a_in);
    const b: Vec3 = broadcast(b_in);
    return Vec3{ .x = a.x / b.x, .y = a.y / b.y, .z = a.z / b.z };
}

fn dot(a: Vec3, b: Vec3) f64 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn cross(a: Vec3, b: Vec3) Vec3 {
    return Vec3{ .x = a.y * b.z - a.z * b.y, .y = a.z * b.x - a.x * b.z, .z = a.x * b.y - a.y * b.x };
}

fn mag(a: Vec3) f64 {
    return @sqrt(dot(a, a));
}

fn normalize(a: Vec3) Vec3 {
    return div(a, mag(a));
}

// settings

const window_w: usize = 1920; // window width in pixels
const window_h: usize = 1080; // window height in pixels
const cp: Vec3 = Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 }; // camera position
const tp: Vec3 = Vec3{ .x = 1.0, .y = 0.0, .z = 0.0 }; // target position
const up: Vec3 = Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 }; // up vector
const fov: f64 = 90.0; // horizontal field of view in degrees

// scene definition

const Sphere = struct {
    c: Vec3, // center
    r: f64, // radius

    // Adapted from Inigo Quilez's ray-sphere intersection routine.
    pub fn intersect(this: Sphere, ro: Vec3, rd: Vec3) ?f64 {
        const oc: Vec3 = sub(ro, this.c);
        const b: f64 = dot(oc, rd);
        const qc: Vec3 = sub(oc, mul(b, rd));
        const h: f64 = this.r * this.r - dot(qc, qc);
        return if (h < 0.0) null else -b - @sqrt(h);
    }
};

const scene = [_]Sphere{
    Sphere{ .c = Vec3{ .x = 0.9, .y = 0.2, .z = 0.2 }, .r = 0.1 },
    Sphere{ .c = Vec3{ .x = 0.8, .y = -0.4, .z = 0.6 }, .r = 0.5 },
    Sphere{ .c = Vec3{ .x = 0.9, .y = 0.0, .z = 0.0 }, .r = 0.1 },
};

// main program

const Pixel = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

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

    const t: Vec3 = normalize(sub(tp, cp)); // target vector
    const b: Vec3 = normalize(cross(t, up)); // horizontal vector
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

    // render a depth map with a single sphere

    // find depth map and limits
    var min_depth: f64 = std.math.floatMax(f64);
    var max_depth: f64 = -std.math.floatMax(f64);
    const depths: []f64 = try allocator.alloc(f64, window_w * window_h);
    @memset(depths, std.math.floatMax(f64));
    for (rays, depths) |*ray, *depth| {
        for (&scene) |*object| {
            if (object.intersect(cp, ray.*)) |dist| {
                depth.* = @min(depth.*, dist);
                min_depth = @min(min_depth, dist);
                max_depth = @max(max_depth, dist);
            }
        }
    }

    // write depth map to frame buffer
    for (frame_buffer, depths) |*pixel, *depth| {
        const scale = (depth.* - min_depth) / (max_depth - min_depth);
        if (scale < 0.0 or scale > 1.0) continue;
        const scale_int: u8 = @intFromFloat(scale * 255.0);
        pixel.r = scale_int;
        pixel.g = scale_int;
        pixel.b = scale_int;
    }

    try writeImage(frame_buffer, "image.ppm");
}
