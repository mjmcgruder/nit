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

// main program

const window_w: usize = 640;
const window_h: usize = 480;

const Pixel = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // initialize image

    const frame_buffer: []Pixel = try allocator.alloc(Pixel, window_w * window_h);
    for (frame_buffer, 0..) |*item, i| {
        const r: usize = i / window_w;
        const c: usize = i - (window_w * r);
        const r_flt: f64 = @floatFromInt(r);
        const c_flt: f64 = @floatFromInt(c);
        const w_flt: f64 = @floatFromInt(window_w);
        const h_flt: f64 = @floatFromInt(window_h);
        item.*.r = @intFromFloat((c_flt / w_flt) * 255.0);
        item.*.g = @intFromFloat((r_flt / h_flt) * 255.0);
        item.*.b = 0;
    }

    // write image

    const file: std.fs.File = try std.fs.cwd().createFile("image.ppm", .{});
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
