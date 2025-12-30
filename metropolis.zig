const std = @import("std");

const m = @import("src/math.zig");
const io = @import("src/io.zig");
const smp = @import("src/sampling.zig");
const geom = @import("src/geometry.zig");

test {
    _ = m;
    _ = io;
    _ = smp;
    _ = geom;
}

var stdout_writer = std.fs.File.stdout().writer(&.{});
var stderr_writer = std.fs.File.stderr().writer(&.{});
const stdout = &stdout_writer.interface;
const stderr = &stderr_writer.interface;

var render_timer: std.time.Timer = undefined;
const chunk_size: usize = 1 << 11;

var last_print_time: u64 = undefined;
var last_print_mutex = std.Thread.Mutex{};

var chunk_start: usize = 0;
var chunk_mutex = std.Thread.Mutex{};

var finished_pixels: usize = 0;

fn dispatchRender(
    rays: []const m.Vec3,
    scene: []const geom.Object,
    settings: *const io.Settings,
    thread_num: usize,
    frame_buffer: []io.Pixel,
) !void {
    var rng: smp.PCGHash = smp.PCGHash{ .state = @as(u32, @intCast(42 + thread_num)) };
    while (chunk_start < frame_buffer.len) {
        if (chunk_mutex.tryLock()) {
            const chunk_end: usize = @min(chunk_start + chunk_size, frame_buffer.len);
            const chunk_start_current: usize = chunk_start;
            chunk_start = chunk_end;
            chunk_mutex.unlock();
            try renderPixels(
                rays,
                scene,
                settings,
                &rng,
                chunk_start_current,
                chunk_end,
                frame_buffer,
            );
        }
    }
}

const BounceNode = struct {
    brdf: m.Vec3 = m.Vec3{ .data = .{ 0.0, 0.0, 0.0 } },
    emit: m.Vec3 = m.Vec3{ .data = .{ 0.0, 0.0, 0.0 } },
    c_th: f32 = 0.0,
    prob: f32 = 1.0,
};

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

fn intersectScene(ro: m.Vec3, rd: m.Vec3, scene: []const geom.Object) ?geom.IntersectResult {
    var intersect = geom.IntersectResult{
        .geom = .{ .dist = std.math.floatMax(f32), .norm = undefined },
        .refl = undefined,
        .emit = undefined,
        .mtrl = undefined,
    };
    for (scene) |object| {
        if (geom.intersectRayObject(.{ .o = ro, .d = rd }, object)) |result| {
            if (result.geom.dist < intersect.geom.dist) {
                intersect = result;
            }
        }
    }
    return if (intersect.geom.dist == std.math.floatMax(f32)) null else intersect;
}

fn renderPixels(
    rays: []const m.Vec3,
    scene: []const geom.Object,
    settings: *const io.Settings,
    rng: *smp.PCGHash,
    begin_i: usize,
    end_i: usize,
    frame_buffer: []io.Pixel,
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

        const current_time = render_timer.read();
        if (current_time - last_print_time > 100000000) {
            try printRenderProgress(current_time, frame_buffer.len);
        }

        // render

        const initial_ray: *const m.Vec3 = &rays[pixel_i];
        const pixel: *io.Pixel = &frame_buffer[pixel_i];

        var sample_i: usize = 0;
        var pixel_color: m.Vec3 = m.Vec3{ .data = .{ 0.0, 0.0, 0.0 } };
        sample_loop: while (sample_i < settings.num_samples) : (sample_i += 1) {
            stack_i = 0;

            // build bounce stack
            var ro: m.Vec3 = settings.camera_position;
            var rd: m.Vec3 = initial_ray.*;
            bounce_loop: while (stack_i < max_bounces) : (stack_i += 1) {
                if (intersectScene(ro, rd, scene)) |intersect| {
                    var new_ray: m.Vec3 = undefined;
                    switch (intersect.mtrl) {
                        geom.Material.diffuse => {
                            new_ray = smp.sampleHemisphere(intersect.geom.norm, rng);
                            bounce_stack[stack_i] = BounceNode{
                                .brdf = m.mul(intersect.refl, 1.0 / std.math.pi),
                                .emit = intersect.emit,
                                .c_th = m.dot(new_ray, intersect.geom.norm),
                                .prob = 1.0 / (2.0 * std.math.pi),
                            };
                        },
                        geom.Material.specular => {
                            new_ray = smp.reflect(intersect.geom.norm, m.mul(rd, -1.0));
                            bounce_stack[stack_i] = BounceNode{
                                .brdf = m.mul(
                                    intersect.refl,
                                    m.sdiv(1.0, m.dot(new_ray, intersect.geom.norm)),
                                ),
                                .emit = intersect.emit,
                                .c_th = m.dot(new_ray, intersect.geom.norm),
                                .prob = 1.0,
                            };
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
            var incoming: m.Vec3 = m.Vec3{}; // start black
            while (stack_i > 0) {
                stack_i -= 1;
                const node: BounceNode = bounce_stack[stack_i];
                incoming = m.add(
                    node.emit,
                    m.mul(m.mul(m.mul(node.brdf, incoming), node.c_th), 1.0 / node.prob),
                );
            }

            // average sample color into pixel color
            pixel_color = m.add(
                pixel_color,
                m.mul(incoming, 1.0 / @as(f32, @floatFromInt(settings.num_samples))),
            );
        }

        // set final color value

        pixel.r = @intFromFloat(m.clamp(pixel_color.data[0], 0.0, 1.0) * 255.0);
        pixel.g = @intFromFloat(m.clamp(pixel_color.data[1], 0.0, 1.0) * 255.0);
        pixel.b = @intFromFloat(m.clamp(pixel_color.data[2], 0.0, 1.0) * 255.0);
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

pub fn main() !void {
    // preliminaries

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator: std.mem.Allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // if (args.len != 2) {
    //     try stdout.print("  usage: metropolis <input_file>\n", .{});
    //     return;
    // }

    // var settings = io.Settings{};
    // var scene_list = std.ArrayList(geom.Object).empty;
    // try io.readInput(allocator, args[1], &settings, &scene_list);
    // const scene: []geom.Object = scene_list.items;
    // defer scene_list.deinit(allocator);

    const settings = io.Settings{};
    var scene_list = [_]geom.Object{
        geom.Object{
            .geom = geom.GeometryType{ .box = .{ .size = .{ .data = .{ 1.5, 0.75, 1.5 } } } },
            .trfm = m.translate(.{ .data = .{ 1.0, 0.0, 0.0 } }),
            .refl = .{ .data = .{ 1.0, 1.0, 1.0 } },
            .emit = .{ .data = .{ 0.0, 0.0, 0.0 } },
            .mtrl = geom.Material.diffuse,
        },
        geom.Object{
            .geom = geom.GeometryType{ .box = .{ .size = .{ .data = .{ 0.2, 0.2, 0.2 } } } },
            .trfm = m.translate(.{ .data = .{ 2.0, 0.75 + 0.2 * 0.99, 0.0 } }),
            .refl = .{ .data = .{ 1.0, 0.0, 0.0 } },
            .emit = .{ .data = .{ 12.0, 12.0, 12.0 } },
            .mtrl = geom.Material.diffuse,
        },
        geom.Object{
            .geom = geom.GeometryType{ .box = .{ .size = .{ .data = .{ 0.2, 0.2, 0.2 } } } },
            .trfm = m.matmul4(
                m.translate(.{ .data = .{ 1.9, -0.75 + 0.2, 0.5 } }),
                m.rotateAboutAxis(.{ .data = .{ 0.0, 1.0, 0.0 } }, -15.0),
            ),
            .refl = .{ .data = .{ 0.2, 1.0, 0.2 } },
            .emit = .{ .data = .{ 0.0, 0.0, 0.0 } },
            .mtrl = geom.Material.diffuse,
        },
        geom.Object{
            .geom = geom.GeometryType{ .box = .{ .size = .{ .data = .{ 0.2, 0.4, 0.2 } } } },
            .trfm = m.matmul4(
                m.translate(.{ .data = .{ 2.1, -0.75 + 0.4, -0.6 } }),
                m.rotateAboutAxis(.{ .data = .{ 0.0, 1.0, 0.0 } }, 35.0),
            ),
            .refl = .{ .data = .{ 1.0, 0.2, 0.2 } },
            .emit = .{ .data = .{ 0.0, 0.0, 0.0 } },
            .mtrl = geom.Material.diffuse,
        },
        geom.Object{
            .geom = geom.GeometryType{ .sphere = .{ .r = 0.2 } },
            .trfm = m.translate(.{ .data = .{ 1.5, -0.75 + 0.2, 0.0 } }),
            .refl = .{ .data = .{ 1.0, 1.0, 1.0 } },
            .emit = .{ .data = .{ 0.0, 0.0, 0.0 } },
            .mtrl = geom.Material.specular,
        },
        geom.Object{
            .geom = geom.GeometryType{ .mesh = try io.readASCIISTL("Suzanne.stl", allocator) }, // TODO: deinit this? (arena takes care of it in this case but still?)
            .trfm = m.matmul4(m.translate(.{ .data = .{ 2.0, 0.0, 0.6 } }), m.matmul4(m.rotateAboutAxis(.{ .data = .{ 0.0, 1.0, 1.0 } }, -110.0), m.scale(0.4))),
            .refl = .{ .data = .{ 0.2, 0.2, 1.0 } },
            .emit = .{ .data = .{ 0.0, 0.0, 0.0 } },
            .mtrl = geom.Material.diffuse,
        },
    };

    const scene: []geom.Object = &scene_list;

    // initialization

    const frame_buffer: []io.Pixel = try allocator.alloc(
        io.Pixel,
        settings.window_w * settings.window_h,
    );
    @memset(frame_buffer, io.Pixel{});

    // initialize rays

    try stdout.print("  initializing rays...\n", .{});
    const rays: []m.Vec3 = try initializePerspectiveRays(settings, allocator);
    defer allocator.free(rays);

    // render diffuse reflection

    try stdout.print("  rendering...\n", .{});

    render_timer = try std.time.Timer.start();
    last_print_time = 0;

    const pool = try allocator.alloc(std.Thread, settings.thread_count);
    for (pool, 0..) |*thread, thread_num| {
        thread.* = try std.Thread.spawn(.{}, dispatchRender, .{
            rays,
            scene,
            &settings,
            thread_num,
            frame_buffer,
        });
    }
    for (pool) |thread| {
        thread.join();
    }
    try printRenderProgress(render_timer.read(), frame_buffer.len); // ensure 100% update is printed

    try stdout.print("\n  writing image...\n", .{});
    try io.writeImage(frame_buffer, settings, "image.ppm");
}
