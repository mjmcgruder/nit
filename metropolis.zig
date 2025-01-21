const std = @import("std");
const mth = @import("src/math.zig");
const geom = @import("src/geometry.zig");
const io = @import("src/io.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

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

fn intersectSceneNaive(ro: mth.Vec3, rd: mth.Vec3, scene: []geom.Object) ?geom.IntersectResult {
    var intersect = geom.IntersectResult{
        .d = std.math.floatMax(f32),
        .n = undefined,
        .r = undefined,
        .e = undefined,
        .m = undefined,
    };
    for (scene) |*object| {
        if (object.intersect(ro, rd)) |result| {
            if (result.d < intersect.d) {
                intersect = result;
            }
        }
    }
    return if (intersect.d == std.math.floatMax(f32)) null else intersect;
}

fn randomRayInHemisphere(n: mth.Vec3, rng: *PCG_rng) mth.Vec3 {
    const local_z: mth.Vec3 = n;
    const local_y: mth.Vec3 = mth.normalize(
        mth.cross(local_z, if (@abs(local_z.x) < 0.9) mth.unit_x else mth.unit_y),
    );
    const local_x: mth.Vec3 = mth.normalize(mth.cross(local_y, local_z));
    const theta: f32 = rng.rand_f32() * 2.0 * std.math.pi;
    const u: f32 = rng.rand_f32();
    const r: f32 = @sqrt(1.0 - u * u);
    const x: f32 = r * @cos(theta);
    const y: f32 = r * @sin(theta);
    const z: f32 = u;
    return mth.normalize(
        mth.add(mth.add(mth.mul(local_x, x), mth.mul(local_y, y)), mth.mul(local_z, z)),
    );
}

var timer: std.time.Timer = undefined;
const chunk_size: usize = 1 << 11;

var last_print_time: u64 = undefined;
var last_print_mutex: std.Thread.Mutex = std.Thread.Mutex{};

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

const Pixel = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

fn dispatchRender(
    rays: []mth.Vec3,
    scene: []geom.Object,
    settings: io.Settings,
    thread_num: usize,
    frame_buffer: []Pixel,
) !void {
    var rng: PCG_rng = PCG_rng{ .state = @as(u32, @intCast(42 + thread_num)) };
    while (chunk_start < frame_buffer.len) {
        if (chunk_mutex.tryLock()) {
            const chunk_end = @min(chunk_start + chunk_size, frame_buffer.len);
            const chunk_start_current = chunk_start;
            chunk_start = chunk_end;
            chunk_mutex.unlock();
            try renderPixelRange(
                rays,
                scene,
                settings,
                &rng,
                chunk_start_current,
                chunk_end,
                frame_buffer,
            );
            {
                finished_pixels_mutex.lock();
                defer finished_pixels_mutex.unlock();
                finished_pixels += chunk_end - chunk_start_current;
            }
        }
    }
}

const BounceNode = struct {
    brdf: mth.Vec3 = mth.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    emit: mth.Vec3 = mth.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    c_th: f32 = 0.0,
    prob: f32 = 1.0,
};

fn renderPixelRange(
    rays: []mth.Vec3,
    scene: []geom.Object,
    settings: io.Settings,
    rng: *PCG_rng,
    begin_i: usize,
    end_i: usize,
    frame_buffer: []Pixel,
) !void {
    const max_bounces: usize = 1 << 3;
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

        const initial_ray: *mth.Vec3 = &rays[pixel_i];
        const pixel: *Pixel = &frame_buffer[pixel_i];

        var sample_i: usize = 0;
        var pixel_color: mth.Vec3 = mth.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 };
        while (sample_i < settings.num_samples) : (sample_i += 1) {
            stack_i = 0;

            // build bounce stack
            var ro: mth.Vec3 = settings.camera_position;
            var rd: mth.Vec3 = initial_ray.*;
            while (stack_i < max_bounces) : (stack_i += 1) {
                if (intersectSceneNaive(ro, rd, scene)) |intersect| {
                    var new_ray: mth.Vec3 = undefined;
                    switch (intersect.m) {
                        geom.Material.diffuse => {
                            new_ray = randomRayInHemisphere(intersect.n, rng);
                            bounce_stack[stack_i] = BounceNode{
                                .brdf = mth.mul(intersect.r, 1.0 / std.math.pi),
                                .emit = intersect.e,
                                .c_th = mth.dot(new_ray, intersect.n),
                                .prob = 1.0 / (2.0 * std.math.pi),
                            };
                        },
                        geom.Material.specular => {
                            const wo: mth.Vec3 = mth.mul(rd, -1.0); // source light direction
                            new_ray = mth.normalize(mth.sub(mth.mul(2.0, mth.mul(mth.dot(intersect.n, wo), intersect.n)), wo));
                            const inv_cos_thetar = 1.0 / mth.dot(new_ray, intersect.n);
                            bounce_stack[stack_i] = BounceNode{
                                .brdf = mth.mul(intersect.r, inv_cos_thetar),
                                .emit = intersect.e,
                                .c_th = mth.dot(new_ray, intersect.n),
                                .prob = 1.0,
                            };
                        },
                    }
                    ro = mth.add(ro, mth.mul(rd, intersect.d));
                    rd = new_ray;
                } else {
                    break;
                }
            }

            // accumulate incoming color by unwinding bounce stack
            var incoming: mth.Vec3 = mth.Vec3{}; // start black
            while (stack_i > 0) {
                stack_i -= 1;
                const node: BounceNode = bounce_stack[stack_i];
                incoming = mth.add(
                    node.emit,
                    mth.mul(mth.mul(mth.mul(node.brdf, incoming), node.c_th), 1.0 / node.prob),
                );
            }

            // average sample color into pixel color
            pixel_color = mth.add(
                pixel_color,
                mth.mul(incoming, 1.0 / @as(f32, @floatFromInt(settings.num_samples))),
            );
        }

        // set final color value

        pixel_color.x = mth.clamp(pixel_color.x, 0.0, 1.0);
        pixel_color.y = mth.clamp(pixel_color.y, 0.0, 1.0);
        pixel_color.z = mth.clamp(pixel_color.z, 0.0, 1.0);
        pixel.r = @intFromFloat(pixel_color.x * 255.0);
        pixel.g = @intFromFloat(pixel_color.y * 255.0);
        pixel.b = @intFromFloat(pixel_color.z * 255.0);
    }
}

fn writeImage(frame_buffer: []const Pixel, settings: io.Settings, file_name: []const u8) !void {
    const file: std.fs.File = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();
    var buffer_wrapper = std.io.bufferedWriter(file.writer());
    var file_writer = buffer_wrapper.writer();

    try file_writer.print("P3\n", .{});
    try file_writer.print("{d} {d}\n", .{ settings.window_w, settings.window_h });
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
    defer std.process.argsFree(arena, args); // TODO: still needed with arena?

    if (args.len != 2) {
        try stdout.print("  usage: metropolis <input_file>\n", .{});
        return;
    }

    var settings: io.Settings = io.Settings{};
    var scene_list: std.ArrayList(geom.Object) = std.ArrayList(geom.Object).init(arena);
    try io.readInput(args[1], &settings, &scene_list);
    const scene: []geom.Object = scene_list.items;
    defer scene_list.deinit(); // TODO: still needed with arena?

    // initialize image

    const frame_buffer: []Pixel = try arena.alloc(Pixel, settings.window_w * settings.window_h);
    @memset(frame_buffer, Pixel{});

    // initialize rays

    try stdout.print("  initializing rays...\n", .{});

    const window_h_flt: f32 = @floatFromInt(settings.window_h);
    const window_w_flt: f32 = @floatFromInt(settings.window_w);

    const t: mth.Vec3 = mth.normalize(mth.sub(settings.target_position, settings.camera_position)); // target vector
    const b: mth.Vec3 = mth.normalize(mth.cross(t, settings.up_vector)); // horizontal vector
    const v: mth.Vec3 = mth.normalize(mth.cross(b, t)); // vertical vector

    const hw: f32 = @tan(0.5 * settings.field_of_view); // view port half width and height at distance 1
    const hh: f32 = hw * ((window_h_flt - 1.0) / (window_w_flt - 1.0));

    const ul: mth.Vec3 = mth.add(mth.sub(t, mth.mul(hw, b)), mth.mul(hh, v)); // upper left point
    const inc_w: f32 = (2.0 * hw) / (window_w_flt - 1.0);
    const inc_h: f32 = (2.0 * hh) / (window_h_flt - 1.0);

    const rays: []mth.Vec3 = try arena.alloc(mth.Vec3, settings.window_w * settings.window_h);
    for (rays, 0..) |*item, i| {
        const r: usize = i / settings.window_w;
        const c: usize = i - (settings.window_w * r);
        const r_flt: f32 = @floatFromInt(r);
        const c_flt: f32 = @floatFromInt(c);
        item.* = mth.normalize(
            mth.add(ul, mth.add(mth.mul(-inc_h * r_flt, v), mth.mul(inc_w * c_flt, b))),
        );
    }

    // render diffuse reflection

    try stdout.print("  rendering...\n", .{});

    const pool = try arena.alloc(std.Thread, settings.thread_count);
    for (pool, 0..) |*thread, thread_num| {
        thread.* = try std.Thread.spawn(.{}, dispatchRender, .{
            rays,
            scene,
            settings,
            thread_num,
            frame_buffer,
        });
    }
    for (pool) |thread| {
        thread.join();
    }
    try printRenderProgress(timer.read(), frame_buffer.len); // ensure 100% update is printed

    try stdout.print("\n  writing image...\n", .{});

    try writeImage(frame_buffer, settings, "image.ppm");
}
