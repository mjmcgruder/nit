const std = @import("std");

const io = @import("src/io.zig");
const math = @import("src/math.zig");
const samp = @import("src/sampling.zig");
const rand = @import("src/random.zig");
const geom = @import("src/geometry.zig");
const rend = @import("src/rendering.zig");
const prim = @import("src/geometry_primitives.zig");
const misc = @import("src/misc.zig");

test {
    _ = math;
    _ = io;
    _ = samp;
    _ = geom;
}

const chunk_size: usize = 1 << 11;

const print_interval: f64 = 0.1;
const print_precision: usize = @intFromFloat(@abs(@min(@log10(print_interval), 0.0)));
var render_start_time: std.Io.Timestamp = undefined;
var last_print_time: std.Io.Timestamp = undefined;
var last_print_mutex: std.Io.Mutex = .init;

var chunk_start: usize = 0;
var chunk_mutex: std.Io.Mutex = .init;

var finished_pixels: usize = 0;

fn dispatchRender(
    frame_info: FrameInfo,
    scene: geom.Scene,
    settings: *const io.Settings,
    thread_num: usize,
    frame_buffer: []io.Pixel,
    stdio: std.Io,
) !void {
    var rng: rand.PCGHash = rand.PCGHash{ .state = @as(u32, @intCast(42 + thread_num)) };
    while (chunk_start < frame_buffer.len) {
        if (chunk_mutex.tryLock()) {
            const chunk_end: usize = @min(chunk_start + chunk_size, frame_buffer.len);
            const chunk_start_current: usize = chunk_start;
            chunk_start = chunk_end;
            chunk_mutex.unlock(stdio);
            try render(
                frame_info,
                scene,
                settings,
                &rng,
                chunk_start_current,
                chunk_end,
                frame_buffer,
                stdio,
            );
        }
    }
}

fn printRenderProgress(
    current_time: std.Io.Timestamp,
    total_pixels: u64,
    stdio: std.Io,
    comptime precision: usize,
) !void {
    if (last_print_mutex.tryLock()) {
        defer last_print_mutex.unlock(stdio);
        last_print_time = current_time;
        var stdout = misc.StdOut.init(stdio);
        try stdout.print("\x1b[1K\r", .{});
        try stdout.print(
            "   {d:5.1}% {d:.[2]}s",
            .{
                @as(f32, @floatFromInt(finished_pixels)) / @as(f32, @floatFromInt(total_pixels)) * 100.0,
                misc.duration(render_start_time, current_time),
                precision
            },
        );
    }
}

fn render(
    frame_info: FrameInfo,
    scene: geom.Scene,
    settings: *const io.Settings,
    rng: *rand.PCGHash,
    begin_i: usize,
    end_i: usize,
    frame_buffer: []io.Pixel,
    stdio: std.Io,
) !void {
    for (begin_i..end_i) |pixel_i| {
        // count each pixel for output progress update purposes
        _ = @atomicRmw(
            usize,
            &finished_pixels,
            std.lang.AtomicRmwOp.Add,
            1,
            std.lang.AtomicOrder.acq_rel,
        );

        // occasionally print a progress update
        const current_time: std.Io.Timestamp = std.Io.Clock.awake.now(stdio);
        if (misc.duration(last_print_time, current_time) > print_interval) {
            try printRenderProgress(current_time, frame_buffer.len, stdio, print_precision);
        }

        // render
        const ray: prim.Ray = .{
            .o = settings.camera_position,
            .d = findCameraRay(pixel_i, frame_info),
        };
        const pixel_color = switch (settings.renderer) {
            .depth => rend.renderDepth(ray, scene),
            .direct_lighting => rend.renderDirectLighting(ray, scene, settings.num_samples, rng),
            .path_tracing => rend.render(ray, scene, settings.num_samples, rng),
        };

        // set final color value
        const pixel: *io.Pixel = &frame_buffer[pixel_i];
        std.debug.assert(!std.math.isNan(pixel_color[0]));
        pixel.r = @intFromFloat(math.clamp(pixel_color[0], 0.0, 1.0) * 255.0);
        std.debug.assert(!std.math.isNan(pixel_color[1]));
        pixel.g = @intFromFloat(math.clamp(pixel_color[1], 0.0, 1.0) * 255.0);
        std.debug.assert(!std.math.isNan(pixel_color[2]));
        pixel.b = @intFromFloat(math.clamp(pixel_color[2], 0.0, 1.0) * 255.0);
    }
}

const FrameInfo = struct {
    ulft: math.Vec3, // upper left corner
    // pixel counts ("h"-horizontal, "v"-vertical)
    npxh: usize,
    npxv: usize,
    // (normalized) reference plane direction vectors
    vech: math.Vec3,
    vecv: math.Vec3, // this points down
    // pixel sizes (increments) at the reference plane
    inch: f32,
    incv: f32,
};

fn findCameraRay(pi: usize, f: FrameInfo) math.Vec3 {
    const posv: f32 = @as(f32, @floatFromInt(pi / f.npxh)) + 0.5;
    const posh: f32 = @as(f32, @floatFromInt(pi % f.npxh)) + 0.5;
    return math.normalize(
        math.add(
            f.ulft,
            math.add(
                math.mul(f.incv * posv, f.vecv),
                math.mul(f.inch * posh, f.vech),
            ),
        ),
    );
}

fn initializeFrameInfo(settings: io.Settings) !FrameInfo {
    const window_h_flt: f32 = @floatFromInt(settings.window_h);
    const window_w_flt: f32 = @floatFromInt(settings.window_w);

    const t: math.Vec3 = math.normalize(math.sub(settings.target_position, settings.camera_position)); // target vector
    const b: math.Vec3 = math.normalize(math.cross(t, settings.up_vector)); // horizontal vector
    const v: math.Vec3 = math.normalize(math.cross(b, t)); // vertical vector

    // view port half width and height at distance 1
    const hw: f32 = @tan(0.5 * settings.field_of_view * (std.math.pi / 180.0));
    const hh: f32 = hw * (window_h_flt / window_w_flt);

    const ul: math.Vec3 = math.add(math.sub(t, math.mul(hw, b)), math.mul(hh, v)); // upper left point
    const inc_w: f32 = (2.0 * hw) / (window_w_flt);
    const inc_h: f32 = (2.0 * hh) / (window_h_flt);

    return FrameInfo{
        .ulft = ul,
        .npxh = settings.window_w,
        .npxv = settings.window_h,
        .vech = b,
        .vecv = math.mul(-1.0, v),
        .inch = inc_w,
        .incv = inc_h,
    };
}

pub fn main(init: std.process.Init.Minimal) !void {

    // preprocess

    var io_instance: std.Io.Threaded = .init_single_threaded;
    const stdio = io_instance.io();

    var allocator_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer allocator_instance.deinit();
    const allocator: std.mem.Allocator = allocator_instance.allocator();

    var stdout = misc.StdOut.init(stdio);

    const args = try init.args.toSlice(allocator);
    if (args.len != 2) {
        try stdout.print("  usage: {s} <input_file>\n", .{args[0]});
        return;
    }

    try stdout.print("\n\npreprocessing...\n\n\n", .{});

    const settings: io.Settings, const scene: geom.Scene = try io.readInput(args[1], allocator, stdio);

    // render

    try stdout.print("\n\nrendering...\n\n\n", .{});

    const frame_buffer: []io.Pixel = try allocator.alloc(
        io.Pixel,
        settings.window_w * settings.window_h,
    );
    @memset(frame_buffer, .{});

    render_start_time = std.Io.Clock.awake.now(stdio);
    try printRenderProgress(render_start_time, frame_buffer.len, stdio, print_precision);

    const pool = try allocator.alloc(std.Thread, settings.thread_count);
    for (pool, 0..) |*thread, thread_num| {
        thread.* = try std.Thread.spawn(.{}, dispatchRender, .{
            try initializeFrameInfo(settings),
            scene,
            &settings,
            thread_num,
            frame_buffer,
            stdio,
        });
    }
    for (pool) |thread| {
        thread.join();
    }

    // ensure 100% update is printed
    const render_stop_time: std.Io.Timestamp = std.Io.Clock.awake.now(stdio);
    try printRenderProgress(render_stop_time, frame_buffer.len, stdio, 3);

    // finalize

    try stdout.print("\n  writing image...\n", .{});
    try io.writeImage(stdio, frame_buffer, settings, "image.ppm");
}
