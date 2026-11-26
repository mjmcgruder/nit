const std = @import("std");

const math = @import("math.zig");
const geom = @import("geometry.zig");
const rend = @import("rendering.zig");
const misc = @import("misc.zig");
const geom_mesh = @import("geometry_mesh.zig");

const Vec3 = math.Vec3;
const Vec4 = math.Vec4;
const Vec3c = math.Vec3c;

pub const Settings = struct {
    renderer: rend.Renderers = .path_tracing,
    thread_count: usize = 8,
    num_samples: usize = 1 << 0,
    window_w: usize = 1920,
    window_h: usize = 1080,
    camera_position: Vec3 = .{ 0.0, 0.0, 0.0 },
    target_position: Vec3 = .{ 1.0, 0.0, 0.0 },
    up_vector: Vec3 = .{ 0.0, 1.0, 0.0 },
    field_of_view: f32 = 90.0,
};

pub const Pixel = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

pub fn writeImage(io: std.Io, frame_buffer: []const Pixel, settings: Settings, file_name: []const u8) !void {
    const file: std.Io.File = try std.Io.Dir.cwd().createFile(io, file_name, .{});
    defer file.close(io);

    var write_buffer: [1 << 12]u8 = undefined;
    var file_writer = file.writer(io, &write_buffer);
    const writer = &file_writer.interface;

    try writer.print("P3\n", .{});
    try writer.print("{d} {d}\n", .{ settings.window_w, settings.window_h });
    try writer.print("255\n", .{});
    for (frame_buffer) |pixel| {
        try writer.print("{d:>3} {d:>3} {d:>3}\n", .{ pixel.r, pixel.g, pixel.b });
    }

    try writer.flush();
}

const ParsingError = error{
    FormatError,
    UnknownObjectType,
    UnknownKey,
    UnknownEnumValue,
    NotImplemented,
};

fn parseEnum(enum_type: type, string: []const u8) !enum_type {
    inline for (@typeInfo(enum_type).@"enum".field_names) |name| {
        if (std.mem.eql(u8, string, name)) {
            return @field(enum_type, name);
        }
    }
    return ParsingError.UnknownEnumValue;
}

fn parseVec3(str: []const u8) !Vec3 {
    var it = std.mem.splitScalar(u8, str, ',');
    const elem0 = it.next() orelse return ParsingError.FormatError;
    const elem1 = it.next() orelse return ParsingError.FormatError;
    const elem2 = it.next() orelse return ParsingError.FormatError;
    if (it.next() != null) return ParsingError.FormatError;
    return .{
        try std.fmt.parseFloat(f32, elem0),
        try std.fmt.parseFloat(f32, elem1),
        try std.fmt.parseFloat(f32, elem2),
    };
}

fn parseVec4(str: []const u8) !Vec4 {
    var it = std.mem.splitScalar(u8, str, ',');
    const elem0 = it.next() orelse return ParsingError.FormatError;
    const elem1 = it.next() orelse return ParsingError.FormatError;
    const elem2 = it.next() orelse return ParsingError.FormatError;
    const elem3 = it.next() orelse return ParsingError.FormatError;
    if (it.next() != null) return ParsingError.FormatError;
    return .{
        try std.fmt.parseFloat(f32, elem0),
        try std.fmt.parseFloat(f32, elem1),
        try std.fmt.parseFloat(f32, elem2),
        try std.fmt.parseFloat(f32, elem3),
    };
}

const InputParseMode = enum {
    normal,
    object,
};

const SettingsEnum = std.meta.FieldEnum(Settings);
const settings_map = std.StaticStringMap(SettingsEnum).initComptime(.{
    .{ "num_threads", .thread_count },
    .{ "num_samples", .num_samples },
    .{ "window_width", .window_w },
    .{ "window_height", .window_h },
    .{ "camera_position", .camera_position },
    .{ "target_position", .target_position },
    .{ "up_vector", .up_vector },
    .{ "horizontal_fov", .field_of_view },
    .{ "renderer", .renderer },
});

const ObjectSettingsEnum = enum { geometry, scale, rotate, translate, reflectance, emittance, material };
const object_map = std.StaticStringMap(ObjectSettingsEnum).initComptime(.{
    .{ "geom", .geometry },
    .{ "scale", .scale },
    .{ "rotate", .rotate },
    .{ "translate", .translate },
    .{ "refl", .reflectance },
    .{ "emit", .emittance },
    .{ "mtrl", .material },
});

const geometry_type_map = std.StaticStringMap(std.meta.Tag(geom.GeometryType)).initComptime(.{
    .{ "sphere", .sphere },
    .{ "box", .box },
    .{ "mesh", .mesh },
});

const renderer_map = std.StaticStringMap(rend.Renderers).initComptime(.{
    .{ "depth", .depth },
    .{ "direct", .direct_lighting },
    .{ "path_tracing", .path_tracing },
});

const whitespace: []const u8 = " \t\r\n";

pub fn readInput(
    rel_path: []const u8,
    allocator: std.mem.Allocator,
    io: std.Io,
) !struct { Settings, geom.Scene } {
    var workspace_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer workspace_instance.deinit();
    const workspace: std.mem.Allocator = workspace_instance.allocator();

    var stdout = misc.StdOut.init(io);

    try stdout.print("Reading input file \"{s}\".\n", .{rel_path});

    var settings: Settings = .{};
    var objects: std.ArrayList(geom.Object) = .empty;

    var mode: InputParseMode = .normal;

    const fID: std.Io.File = try std.Io.Dir.cwd().openFile(io, rel_path, .{});
    defer fID.close(io);

    var read_buffer: [1 << 12]u8 = undefined;
    var file_reader = fID.reader(io, &read_buffer);
    const reader = &file_reader.interface;

    var line_num: usize = 1;

    line_loop: while (try reader.takeDelimiter('\n')) |line| : (line_num += 1) {
        errdefer std.log.err("parsing error at line {}", .{line_num});

        var tok = std.mem.tokenizeAny(u8, line, whitespace);
        const word = tok.next() orelse continue :line_loop; // skip blank lines

        // skip comment lines
        if (word[0] == '#') continue :line_loop;

        // change mode if necessary
        if (std.mem.eql(u8, word, "end")) {
            mode = .normal;
            continue :line_loop;
        }
        if (std.mem.eql(u8, word, "object")) {
            mode = .object;
            const type_word = tok.next() orelse return ParsingError.FormatError;

            if (geometry_type_map.get(type_word)) |geom_type| {
                var geometry = geom.GeometryType{ .sphere = .{} };
                switch (geom_type) {
                    .sphere => geometry = geom.GeometryType{ .sphere = .{} },
                    .box => geometry = geom.GeometryType{ .box = .{} },
                    .mesh => geometry = geom.GeometryType{ .mesh = .{} },
                }
                try objects.append(workspace, geom.Object{ .geom = geometry });
                continue :line_loop;
            } else {
                return ParsingError.UnknownObjectType;
            }
        }

        // parse key-value pairs
        const key = word;
        const eq = tok.next() orelse return ParsingError.FormatError;
        if (!std.mem.eql(u8, eq, "=")) return ParsingError.FormatError;
        const val = tok.next() orelse return ParsingError.FormatError;

        // assign info
        switch (mode) {
            .normal => {
                if (settings_map.get(key)) |setting| {
                    switch (setting) {
                        .renderer => settings.renderer = renderer_map.get(val) orelse return ParsingError.UnknownEnumValue,
                        .thread_count => settings.thread_count = try std.fmt.parseInt(usize, val, 10),
                        .num_samples => settings.num_samples = try std.fmt.parseInt(usize, val, 10),
                        .window_w => settings.window_w = try std.fmt.parseInt(usize, val, 10),
                        .window_h => settings.window_h = try std.fmt.parseInt(usize, val, 10),
                        .camera_position => settings.camera_position = try parseVec3(val),
                        .target_position => settings.target_position = try parseVec3(val),
                        .up_vector => settings.up_vector = try parseVec3(val),
                        .field_of_view => settings.field_of_view = try std.fmt.parseFloat(f32, val),
                    }
                } else {
                    return ParsingError.UnknownKey;
                }
            },
            .object => {
                var object: *geom.Object = &objects.items[objects.items.len - 1];

                if (object_map.get(key)) |setting| {
                    var transform: math.Mat4 = math.makeIdentityTransform();

                    switch (setting) {
                        .geometry => {
                            switch (object.geom) {
                                .sphere => |*value| value.* = blk: {
                                    break :blk .{
                                        .c = @splat(0.0),
                                        .r = try std.fmt.parseFloat(f32, val),
                                    };
                                },
                                .box => |*value| value.* = blk: {
                                    const size: Vec3 = try parseVec3(val);
                                    break :blk .{ .min = math.mul(size, -1.0), .max = size };
                                },
                                .mesh => |*value| value.* = blk: {
                                    try stdout.print("Reading ASCII STL file \"{s}\"... ", .{val});
                                    const t0 = std.Io.Clock.awake.now(io);
                                    const raw_mesh = try readASCIISTL(val, workspace, io);
                                    const t1 = std.Io.Clock.awake.now(io);
                                    try stdout.print("done (in {d:.3}s).\n", .{misc.duration(t0, t1)});

                                    try stdout.print("Deduplicating mesh vertices... ", .{});
                                    const t2 = std.Io.Clock.awake.now(io);
                                    var mesh = try geom_mesh.deDupeMesh(raw_mesh, allocator);
                                    const t3 = std.Io.Clock.awake.now(io);
                                    try stdout.print("done ({f} -> {f} vertices in {d:.3}s).\n", .{
                                        misc.fmtComma(raw_mesh.vrt.len),
                                        misc.fmtComma(mesh.vrt.len),
                                        misc.duration(t2, t3),
                                    });

                                    try stdout.print("Building BVH for \"{s}\"... ", .{val});
                                    const t4 = std.Io.Clock.awake.now(io);
                                    const stats = try geom_mesh.buildBVH(&mesh, allocator, 4, 1 << 4);
                                    const t5 = std.Io.Clock.awake.now(io);
                                    try stdout.print("done (in {d:.3}s).\n", .{misc.duration(t4, t5)});
                                    try geom_mesh.printBVHStats(stats, io);

                                    break :blk mesh;
                                },
                            }
                        },
                        .rotate => {
                            const r = try parseVec4(val);
                            transform = math.makeRotateTransform(.{ r[0], r[1], r[2] }, r[3]);
                        },
                        .scale => transform = math.makeScaleTransform(try std.fmt.parseFloat(f32, val)),
                        .translate => transform = math.makeTranslateTransform(try parseVec3(val)),
                        .reflectance => object.refl = try parseVec3(val),
                        .emittance => object.emit = try parseVec3(val),
                        .material => object.mtrl = try parseEnum(geom.Material, val),
                    }

                    object.trfm = math.matmul4(transform, object.trfm);
                } else {
                    return ParsingError.UnknownKey;
                }
            },
        }
    }

    for (objects.items) |*obj| {
        obj.itfm = math.invertTransform(obj.trfm);
    }

    var scene_objects: []geom.Object = try allocator.alloc(geom.Object, objects.items.len);
    @memcpy(scene_objects, objects.items);

    var num_lights: usize = 0;
    for (0..scene_objects.len) |oi| {
        if (math.mag(scene_objects[oi].emit) > 0.0) {
            std.mem.swap(geom.Object, &scene_objects[num_lights], &scene_objects[oi]);
            num_lights += 1;
        }
    }

    return .{ settings, .{ .objects = scene_objects, .num_lights = num_lights } };
}

fn nextLine(r: *std.Io.Reader) ![]u8 {
    return try r.takeDelimiter('\n') orelse ParsingError.FormatError;
}

pub fn readASCIISTL(
    rel_path: []const u8,
    allocator: std.mem.Allocator,
    io: std.Io,
) !geom_mesh.Mesh {
    var read_buffer: [1 << 18]u8 = undefined;
    const file = try std.Io.Dir.cwd().openFile(io, rel_path, .{});
    defer file.close(io);
    var file_reader = file.reader(io, &read_buffer);
    const reader = &file_reader.interface;

    const num_facets: usize = blk: {
        var nfacets: usize = 0;
        while (try reader.takeDelimiter('\n')) |line| {
            var tok = std.mem.tokenizeAny(u8, line, whitespace);
            if (tok.next()) |kw| {
                if (std.mem.eql(u8, kw, "endfacet")) nfacets += 1;
            }
        }
        break :blk nfacets;
    };

    const vrt = try allocator.alloc(Vec3c, num_facets * 3);
    const ind = try allocator.alloc(u32, num_facets * 3);

    try file_reader.seekTo(0);

    const first_line = try nextLine(reader);
    var tok = std.mem.tokenizeAny(u8, first_line, whitespace);
    if (!std.mem.eql(u8, tok.next() orelse return ParsingError.FormatError, "solid"))
        return ParsingError.FormatError;

    var vi: usize = 0;
    while (try reader.takeDelimiter('\n')) |line| {
        tok = std.mem.tokenizeAny(u8, line, whitespace);

        const keyword = tok.next() orelse continue;

        if (std.mem.eql(u8, keyword, "endsolid")) {
            return .{ .vrt = vrt, .ind = ind };
        }

        if (!std.mem.eql(u8, keyword, "facet")) return ParsingError.FormatError;
        if (!std.mem.eql(u8, tok.next() orelse return ParsingError.FormatError, "normal"))
            return ParsingError.FormatError;

        tok = std.mem.tokenizeAny(u8, try nextLine(reader), whitespace);
        if (!std.mem.eql(u8, tok.next() orelse return ParsingError.FormatError, "outer"))
            return ParsingError.FormatError;
        if (!std.mem.eql(u8, tok.next() orelse return ParsingError.FormatError, "loop"))
            return ParsingError.FormatError;

        for (0..3) |_| {
            tok = std.mem.tokenizeAny(u8, try nextLine(reader), whitespace);
            if (!std.mem.eql(u8, tok.next() orelse return ParsingError.FormatError, "vertex"))
                return ParsingError.FormatError;

            var vertex: Vec3c = .{ 0.0, 0.0, 0.0 };
            inline for (0..3) |i| {
                vertex[i] = try std.fmt.parseFloat(f32, tok.next() orelse return ParsingError.FormatError);
            }
            vrt[vi] = vertex;
            ind[vi] = @intCast(vi);
            vi += 1;
        }

        tok = std.mem.tokenizeAny(u8, try nextLine(reader), whitespace);
        if (!std.mem.eql(u8, tok.next() orelse return ParsingError.FormatError, "endloop"))
            return ParsingError.FormatError;

        tok = std.mem.tokenizeAny(u8, try nextLine(reader), whitespace);
        if (!std.mem.eql(u8, tok.next() orelse return ParsingError.FormatError, "endfacet"))
            return ParsingError.FormatError;
    }

    return ParsingError.FormatError; // file ended without "endsolid"
}

test "readInput --- runs" {
    const io = std.testing.io;

    var stdout_w = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_w.interface;

    var alloc_main_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer alloc_main_instance.deinit();
    const alloc_main: std.mem.Allocator = alloc_main_instance.allocator();

    const settings, const scene = try readInput("src/test_data/input.txt", alloc_main, io, stdout);

    try std.testing.expectEqual(settings.renderer, rend.Renderers.depth);
    try std.testing.expectEqual(settings.thread_count, 8);
    try std.testing.expectEqual(settings.num_samples, 1024);
    try std.testing.expectEqual(settings.window_w, 1920);
    try std.testing.expectEqual(settings.window_h, 1080);
    try std.testing.expectEqual(settings.camera_position, @as(Vec3, .{ -2.0, 0.0, 0.0 }));
    try std.testing.expectEqual(settings.target_position, @as(Vec3, .{ 0.0, 0.0, 0.0 }));
    try std.testing.expectEqual(settings.up_vector, @as(Vec3, .{ 0.0, 1.0, 0.0 }));
    try std.testing.expectEqual(settings.field_of_view, 90.0);

    try std.testing.expectEqual(scene[0].geom.sphere.r, 0.1);
    try std.testing.expectEqual(scene[0].trfm, @as(math.Mat4, .{
        .{ 0.8, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.8, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.8, -1.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    }));
    try std.testing.expectEqual(scene[0].refl, @as(Vec3, .{ 1.0, 1.0, 1.0 }));
    try std.testing.expectEqual(scene[0].emit, @as(Vec3, .{ 0.0, 0.0, 0.0 }));
    try std.testing.expectEqual(scene[0].mtrl, geom.Material.specular);

    try std.testing.expectEqual(scene[1].geom.box.size(), @as(Vec3, .{ 1.0, 1.0, 1.0 }));
    try std.testing.expectEqual(scene[1].trfm, @as(math.Mat4, .{
        .{ 0.08047379, -0.031061722, 0.050587934, 0 },
        .{ 0.050587934, 0.08047379, -0.031061722, 0 },
        .{ -0.031061722, 0.050587934, 0.08047379, 1 },
        .{ 0, 0, 0, 1 },
    }));
    try std.testing.expectEqual(scene[1].refl, @as(Vec3, .{ 0.0, 0.0, 0.0 }));
    try std.testing.expectEqual(scene[1].emit, @as(Vec3, .{ 12.0, 12.0, 12.0 }));
    try std.testing.expectEqual(scene[1].mtrl, geom.Material.diffuse);

    const mesh: geom_mesh.Mesh = scene[2].geom.mesh;

    try std.testing.expectEqual(@as(Vec3c, .{ 0.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[0]]);
    try std.testing.expectEqual(@as(Vec3c, .{ 0.0, 0.0, 1.0 }), mesh.vrt[mesh.ind[1]]);
    try std.testing.expectEqual(@as(Vec3c, .{ 0.0, 1.0, 0.0 }), mesh.vrt[mesh.ind[2]]);

    try std.testing.expectEqual(@as(Vec3c, .{ 0.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[3]]);
    try std.testing.expectEqual(@as(Vec3c, .{ 1.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[4]]);
    try std.testing.expectEqual(@as(Vec3c, .{ 0.0, 0.0, 1.0 }), mesh.vrt[mesh.ind[5]]);

    try std.testing.expectEqual(@as(Vec3c, .{ 0.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[6]]);
    try std.testing.expectEqual(@as(Vec3c, .{ 0.0, 1.0, 0.0 }), mesh.vrt[mesh.ind[7]]);
    try std.testing.expectEqual(@as(Vec3c, .{ 1.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[8]]);

    try std.testing.expectEqual(@as(Vec3c, .{ 1.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[9]]);
    try std.testing.expectEqual(@as(Vec3c, .{ 0.0, 0.0, 1.0 }), mesh.vrt[mesh.ind[10]]);
    try std.testing.expectEqual(@as(Vec3c, .{ 0.0, 1.0, 0.0 }), mesh.vrt[mesh.ind[11]]);

    try std.testing.expectEqual(scene[2].trfm, @as(math.Mat4, .{
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    }));
    try std.testing.expectEqual(scene[2].refl, @as(Vec3, .{ 1.0, 1.0, 1.0 }));
    try std.testing.expectEqual(scene[2].emit, @as(Vec3, .{ 0.0, 0.0, 0.0 }));
    try std.testing.expectEqual(scene[2].mtrl, geom.Material.diffuse);
}
