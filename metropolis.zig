const std = @import("std");

const m = @import("src/math.zig");
const io = @import("src/io.zig");
const smp = @import("src/sampling.zig");
const rand = @import("src/random.zig");
const geom = @import("src/geometry.zig");

test {
    _ = m;
    _ = io;
    _ = smp;
    _ = geom;
}

var render_start: std.Io.Clock.Timestamp = undefined;
const chunk_size: usize = 1 << 11;

var last_print_time: u64 = 0; // nanoseconds since render_start
var last_print_mutex: std.Io.Mutex = .init;

var chunk_start: usize = 0;
var chunk_mutex: std.Io.Mutex = .init;

var finished_pixels: usize = 0;

fn dispatchRender(
    rays: []const m.Vec3,
    scene: []const geom.Object,
    settings: *const io.Settings,
    thread_num: usize,
    frame_buffer: []io.Pixel,
    stdio: std.Io,
    stdout: *std.Io.Writer,
) !void {
    var rng: rand.PCGHash = rand.PCGHash{ .state = @as(u32, @intCast(42 + thread_num)) };
    while (chunk_start < frame_buffer.len) {
        if (chunk_mutex.tryLock()) {
            const chunk_end: usize = @min(chunk_start + chunk_size, frame_buffer.len);
            const chunk_start_current: usize = chunk_start;
            chunk_start = chunk_end;
            chunk_mutex.unlock(stdio);
            try renderPixels(
                rays,
                scene,
                settings,
                &rng,
                chunk_start_current,
                chunk_end,
                frame_buffer,
                stdio,
                stdout,
            );
        }
    }
}

const BounceNode = struct {
    brdf: m.Vec3 = .{ 0.0, 0.0, 0.0 },
    emit: m.Vec3 = .{ 0.0, 0.0, 0.0 },
    c_th: f32 = 0.0,
    prob: f32 = 1.0,
};

fn printRenderProgress(
    current_time: u64,
    total_pixels: u64,
    stdio: std.Io,
    stdout: *std.Io.Writer,
) !void {
    if (last_print_mutex.tryLock()) {
        defer last_print_mutex.unlock(stdio);
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

fn renderPixels(
    rays: []const m.Vec3,
    scene: []const geom.Object,
    settings: *const io.Settings,
    rng: *rand.PCGHash,
    begin_i: usize,
    end_i: usize,
    frame_buffer: []io.Pixel,
    stdio: std.Io,
    stdout: *std.Io.Writer,
) !void {
    const max_bounces: usize = 1 << 3;
    var bounce_stack: [max_bounces]BounceNode = undefined;
    var stack_i: usize = undefined;

    var pixel_i: usize = begin_i;
    while (pixel_i < end_i) : (pixel_i += 1) {
        // count each pixel for output progress update purposes

        _ = @atomicRmw(
            usize,
            &finished_pixels,
            std.builtin.AtomicRmwOp.Add,
            1,
            std.builtin.AtomicOrder.acq_rel,
        );

        // occasionally print a progress update

        const current_time: u64 = @intCast(render_start.untilNow(stdio).raw.nanoseconds);
        if (current_time - last_print_time > 100000000) {
            try printRenderProgress(current_time, frame_buffer.len, stdio, stdout);
        }

        // render

        const initial_ray: *const m.Vec3 = &rays[pixel_i];
        const pixel: *io.Pixel = &frame_buffer[pixel_i];

        var sample_i: usize = 0;
        var pixel_color: m.Vec3 = .{ 0.0, 0.0, 0.0 };
        sample_loop: while (sample_i < settings.num_samples) : (sample_i += 1) {
            stack_i = 0;

            // build bounce stack
            var ro: m.Vec3 = settings.camera_position;
            var rd: m.Vec3 = initial_ray.*;
            bounce_loop: while (stack_i < max_bounces) : (stack_i += 1) {
                if (geom.intersectScene(.{ .o = ro, .d = rd }, scene)) |intersect| {
                    var new_ray: m.Vec3 = undefined;
                    switch (intersect.mtrl) {
                        geom.Material.diffuse => {
                            const sample: smp.BRDFSample =
                                smp.sampleLambertianBRDF(intersect.geom.norm, rng);
                            bounce_stack[stack_i] = BounceNode{
                                .brdf = m.mul(intersect.refl, 1.0 / std.math.pi),
                                .emit = intersect.emit,
                                .c_th = sample.p * std.math.pi,
                                .prob = sample.p,
                            };
                            new_ray = sample.dir;
                        },
                        geom.Material.specular => {
                            const sample: smp.BRDFSample =
                                smp.sampleSpecularBRDF(intersect.geom.norm, m.mul(rd, -1.0));
                            bounce_stack[stack_i] = BounceNode{
                                .brdf = m.mul(
                                    intersect.refl,
                                    m.sdiv(1.0, m.dot(sample.dir, intersect.geom.norm)),
                                ),
                                .emit = intersect.emit,
                                .c_th = m.dot(sample.dir, intersect.geom.norm),
                                .prob = sample.p,
                            };
                            new_ray = sample.dir;
                        },
                    }
                    ro = m.add(
                        m.add(ro, m.mul(rd, intersect.geom.dist)),
                        m.mul(intersect.geom.norm, 1e-5),
                    );
                    rd = new_ray;
                } else {
                    if (stack_i == 0) {
                        break :sample_loop;
                    } else {
                        break :bounce_loop;
                    }
                }
            }

            // accumulate incoming color by unwinding bounce stack
            var incoming: m.Vec3 = .{ 0.0, 0.0, 0.0 }; // start black
            while (stack_i > 0) {
                stack_i -= 1;
                const node: BounceNode = bounce_stack[stack_i];
                incoming = m.add(
                    node.emit,
                    m.mul(m.mul(m.mul(node.brdf, incoming), node.c_th), m.sdiv(1.0, node.prob)),
                );
            }

            // average sample color into pixel color
            pixel_color = m.add(
                pixel_color,
                m.mul(incoming, 1.0 / @as(f32, @floatFromInt(settings.num_samples))),
            );
        }

        // set final color value

        std.debug.assert(!std.math.isNan(pixel_color[0]));
        pixel.r = @intFromFloat(m.clamp(pixel_color[0], 0.0, 1.0) * 255.0);
        std.debug.assert(!std.math.isNan(pixel_color[1]));
        pixel.g = @intFromFloat(m.clamp(pixel_color[1], 0.0, 1.0) * 255.0);
        std.debug.assert(!std.math.isNan(pixel_color[2]));
        pixel.b = @intFromFloat(m.clamp(pixel_color[2], 0.0, 1.0) * 255.0);
    }
}

fn initializePerspectiveRays(settings: io.Settings, allocator: std.mem.Allocator) ![]m.Vec3 {
    const window_h_flt: f32 = @floatFromInt(settings.window_h);
    const window_w_flt: f32 = @floatFromInt(settings.window_w);

    const t: m.Vec3 = m.normalize(m.sub(settings.target_position, settings.camera_position)); // target vector
    const b: m.Vec3 = m.normalize(m.cross(t, settings.up_vector)); // horizontal vector
    const v: m.Vec3 = m.normalize(m.cross(b, t)); // vertical vector

    // view port half width and height at distance 1
    const hw: f32 = @tan(0.5 * settings.field_of_view * (std.math.pi / 180.0));
    const hh: f32 = hw * (window_h_flt / window_w_flt);

    const ul: m.Vec3 = m.add(m.sub(t, m.mul(hw, b)), m.mul(hh, v)); // upper left point
    const inc_w: f32 = (2.0 * hw) / (window_w_flt);
    const inc_h: f32 = (2.0 * hh) / (window_h_flt);

    const rays: []m.Vec3 = try allocator.alloc(m.Vec3, settings.window_w * settings.window_h);
    for (rays, 0..) |*item, i| {
        const r: usize = i / settings.window_w;
        const c: usize = i - (settings.window_w * r);
        const r_flt: f32 = @floatFromInt(r);
        const c_flt: f32 = @floatFromInt(c);
        item.* = m.normalize(
            m.add(ul, m.add(m.mul(-inc_h * (r_flt + 0.5), v), m.mul(inc_w * (c_flt + 0.5), b))),
        );
    }

    return rays;
}

pub fn main(init: std.process.Init.Minimal) !void {

    // preprocess

    var io_instance: std.Io.Threaded = .init_single_threaded;
    const stdio = io_instance.io();

    var stdout_w = std.Io.File.stdout().writer(stdio, &.{});
    const stdout = &stdout_w.interface;

    try stdout.print("\n\npreprocessing...\n\n\n", .{});

    var alloc_main_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer alloc_main_instance.deinit();
    const alloc_main: std.mem.Allocator = alloc_main_instance.allocator();

    var alloc_work_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer alloc_work_instance.deinit();
    const alloc_work: std.mem.Allocator = alloc_work_instance.allocator();

    const args = try init.args.toSlice(alloc_main);
    if (args.len != 2) {
        try stdout.print("  usage: metropolis <input_file>\n", .{});
        return;
    }

    const input = try io.readInput(args[1], alloc_main, alloc_work, stdio, stdout);
    _ = alloc_work_instance.reset(.free_all);
    const settings: io.Settings = input.settings;
    const scene: []geom.Object = input.scene.items;

    // render

    try stdout.print("\n\nrendering...\n\n\n", .{});

    const frame_buffer: []io.Pixel = try alloc_main.alloc(
        io.Pixel,
        settings.window_w * settings.window_h,
    );
    @memset(frame_buffer, io.Pixel{});

    const rays: []m.Vec3 = try initializePerspectiveRays(settings, alloc_main);
    defer alloc_main.free(rays);

    render_start = .now(stdio, .awake);
    last_print_time = 0;

    const pool = try alloc_main.alloc(std.Thread, settings.thread_count);
    for (pool, 0..) |*thread, thread_num| {
        thread.* = try std.Thread.spawn(.{}, dispatchRender, .{
            rays,
            scene,
            &settings,
            thread_num,
            frame_buffer,
            stdio,
            stdout,
        });
    }
    for (pool) |thread| {
        thread.join();
    }

    // ensure 100% update is printed
    const final_time: u64 = @intCast(render_start.untilNow(stdio).raw.nanoseconds);
    try printRenderProgress(final_time, frame_buffer.len, stdio, stdout);

    // finalize

    try stdout.print("\n  writing image...\n", .{});
    try io.writeImage(stdio, frame_buffer, settings, "image.ppm");
}
