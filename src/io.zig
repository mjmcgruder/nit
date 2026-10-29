const std = @import("std");

const m = @import("math.zig");
const geom = @import("geometry.zig");
const rend = @import("rendering.zig");
const geom_mesh = @import("geometry_mesh.zig");

pub const Settings = struct {
    renderer: rend.Renderers = .path_tracing,
    thread_count: usize = 8,
    num_samples: usize = 1 << 0,
    window_w: usize = 1920,
    window_h: usize = 1080,
    camera_position: m.Vec3 = .{ 0.0, 0.0, 0.0 },
    target_position: m.Vec3 = .{ 1.0, 0.0, 0.0 },
    up_vector: m.Vec3 = .{ 0.0, 1.0, 0.0 },
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

fn parseVec3(str: []const u8) !m.Vec3 {
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

fn parseVec4(str: []const u8) !m.Vec4 {
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
    stdout: *std.Io.Writer,
) !struct { Settings, []geom.Object } {
    var workspace_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer workspace_instance.deinit();
    const workspace: std.mem.Allocator = workspace_instance.allocator();

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
                    var transform: m.Mat4 = m.makeIdentityTransform();

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
                                    const size: m.Vec3 = try parseVec3(val);
                                    break :blk .{ .min = m.mul(size, -1.0), .max = size };
                                },
                                .mesh => |*value| value.* = blk: {
                                    const raw_mesh = try readASCIISTL(val, workspace, io, stdout);
                                    try stdout.print("Deduplicating mesh vertices... ", .{});
                                    const dedupe_start = std.Io.Clock.awake.now(io).nanoseconds;
                                    var mesh = try geom_mesh.deDupeMesh(raw_mesh, allocator);
                                    const dedupe_stop = std.Io.Clock.awake.now(io).nanoseconds;
                                    const dedupe_duration = @as(f32, @floatFromInt(dedupe_stop - dedupe_start)) / std.time.ns_per_s;
                                    try stdout.print("done ({f} -> {f} vertices in {d:.3}s).\n", .{ fmtComma(raw_mesh.vrt.len), fmtComma(mesh.vrt.len), dedupe_duration });
                                    try stdout.print("Building BVH for \"{s}\"... ", .{val});
                                    const bvh_build_start = std.Io.Clock.awake.now(io).nanoseconds;
                                    const stats = try geom_mesh.buildBVH(&mesh, allocator, 4, 1 << 4);
                                    const bvh_build_stop = std.Io.Clock.awake.now(io).nanoseconds;
                                    const bvh_build_duration = @as(f32, @floatFromInt(bvh_build_stop - bvh_build_start)) / std.time.ns_per_s;
                                    try stdout.print("done (in {d:.3}s).\n", .{bvh_build_duration});
                                    try geom_mesh.printBVHStats(stats, io);
                                    break :blk mesh;
                                },
                            }
                        },
                        .rotate => {
                            const r = try parseVec4(val);
                            transform = m.makeRotateTransform(.{ r[0], r[1], r[2] }, r[3]);
                        },
                        .scale => transform = m.makeScaleTransform(try std.fmt.parseFloat(f32, val)),
                        .translate => transform = m.makeTranslateTransform(try parseVec3(val)),
                        .reflectance => object.refl = try parseVec3(val),
                        .emittance => object.emit = try parseVec3(val),
                        .material => object.mtrl = try parseEnum(geom.Material, val),
                    }

                    object.trfm = m.matmul4(transform, object.trfm);
                } else {
                    return ParsingError.UnknownKey;
                }
            },
        }
    }

    for (objects.items) |*obj| {
        obj.itfm = m.invertTransform(obj.trfm);
    }

    const final_objects: []geom.Object = try allocator.alloc(geom.Object, objects.items.len);
    @memcpy(final_objects, objects.items);

    return .{ settings, final_objects };
}

const STLReadError = error{ // TODO: possibly generalize this
    FormatError,
    FacetLimitExceeded,
};

fn nextLine(r: *std.Io.Reader) ![]u8 {
    return try r.takeDelimiter('\n') orelse ParsingError.FormatError;
}

pub fn readASCIISTL(
    rel_path: []const u8,
    allocator: std.mem.Allocator,
    io: std.Io,
    stdout: *std.Io.Writer,
) !geom_mesh.Mesh {
    try stdout.print("Reading ASCII STL file \"{s}\"... ", .{rel_path});

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

    const vrt = try allocator.alloc(m.Vec3c, num_facets * 3);
    const ind = try allocator.alloc(u32, num_facets * 3);

    try file_reader.seekTo(0);

    const first_line = try nextLine(reader);
    var tok = std.mem.tokenizeAny(u8, first_line, whitespace);
    if (!std.mem.eql(u8, tok.next() orelse return STLReadError.FormatError, "solid"))
        return STLReadError.FormatError;

    var vi: usize = 0;
    while (try reader.takeDelimiter('\n')) |line| {
        tok = std.mem.tokenizeAny(u8, line, whitespace);

        const keyword = tok.next() orelse continue;

        if (std.mem.eql(u8, keyword, "endsolid")) {
            try stdout.print("done.\n", .{});
            return .{ .vrt = vrt, .ind = ind };
        }

        if (!std.mem.eql(u8, keyword, "facet")) return STLReadError.FormatError;
        if (!std.mem.eql(u8, tok.next() orelse return STLReadError.FormatError, "normal"))
            return STLReadError.FormatError;

        tok = std.mem.tokenizeAny(u8, try nextLine(reader), whitespace);
        if (!std.mem.eql(u8, tok.next() orelse return STLReadError.FormatError, "outer"))
            return STLReadError.FormatError;
        if (!std.mem.eql(u8, tok.next() orelse return STLReadError.FormatError, "loop"))
            return STLReadError.FormatError;

        for (0..3) |_| {
            tok = std.mem.tokenizeAny(u8, try nextLine(reader), whitespace);
            if (!std.mem.eql(u8, tok.next() orelse return STLReadError.FormatError, "vertex"))
                return STLReadError.FormatError;

            var vertex: m.Vec3c = .{ 0.0, 0.0, 0.0 };
            inline for (0..3) |i| {
                vertex[i] = try std.fmt.parseFloat(f32, tok.next() orelse return STLReadError.FormatError);
            }
            vrt[vi] = vertex;
            ind[vi] = @intCast(vi);
            vi += 1;
        }

        tok = std.mem.tokenizeAny(u8, try nextLine(reader), whitespace);
        if (!std.mem.eql(u8, tok.next() orelse return STLReadError.FormatError, "endloop"))
            return STLReadError.FormatError;

        tok = std.mem.tokenizeAny(u8, try nextLine(reader), whitespace);
        if (!std.mem.eql(u8, tok.next() orelse return STLReadError.FormatError, "endfacet"))
            return STLReadError.FormatError;
    }

    return STLReadError.FormatError; // file ended without "endsolid"
}

test "readInput --- runs" {
    const io = std.testing.io;

    var stdout_w = std.Io.File.stdout().writer(io, &.{});
    const stdout = &stdout_w.interface;

    var alloc_main_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer alloc_main_instance.deinit();
    const alloc_main: std.mem.Allocator = alloc_main_instance.allocator();
    var alloc_work_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer alloc_work_instance.deinit();
    const alloc_work: std.mem.Allocator = alloc_work_instance.allocator();

    const settings, const scene = try readInput("src/test_data/input.txt", alloc_main, alloc_work, io, stdout);

    try std.testing.expectEqual(settings.renderer, rend.Renderers.depth);
    try std.testing.expectEqual(settings.thread_count, 8);
    try std.testing.expectEqual(settings.num_samples, 1024);
    try std.testing.expectEqual(settings.window_w, 1920);
    try std.testing.expectEqual(settings.window_h, 1080);
    try std.testing.expectEqual(settings.camera_position, @as(m.Vec3, .{ -2.0, 0.0, 0.0 }));
    try std.testing.expectEqual(settings.target_position, @as(m.Vec3, .{ 0.0, 0.0, 0.0 }));
    try std.testing.expectEqual(settings.up_vector, @as(m.Vec3, .{ 0.0, 1.0, 0.0 }));
    try std.testing.expectEqual(settings.field_of_view, 90.0);

    try std.testing.expectEqual(scene[0].geom.sphere.r, 0.1);
    try std.testing.expectEqual(scene[0].trfm, @as(m.Mat4, .{
        .{ 0.8, 0.0, 0.0, 0.0 },
        .{ 0.0, 0.8, 0.0, 0.0 },
        .{ 0.0, 0.0, 0.8, -1.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    }));
    try std.testing.expectEqual(scene[0].refl, @as(m.Vec3, .{ 1.0, 1.0, 1.0 }));
    try std.testing.expectEqual(scene[0].emit, @as(m.Vec3, .{ 0.0, 0.0, 0.0 }));
    try std.testing.expectEqual(scene[0].mtrl, geom.Material.specular);

    try std.testing.expectEqual(scene[1].geom.box.size(), @as(m.Vec3, .{ 1.0, 1.0, 1.0 }));
    try std.testing.expectEqual(scene[1].trfm, @as(m.Mat4, .{
        .{ 0.08047379, -0.031061722, 0.050587934, 0 },
        .{ 0.050587934, 0.08047379, -0.031061722, 0 },
        .{ -0.031061722, 0.050587934, 0.08047379, 1 },
        .{ 0, 0, 0, 1 },
    }));
    try std.testing.expectEqual(scene[1].refl, @as(m.Vec3, .{ 0.0, 0.0, 0.0 }));
    try std.testing.expectEqual(scene[1].emit, @as(m.Vec3, .{ 12.0, 12.0, 12.0 }));
    try std.testing.expectEqual(scene[1].mtrl, geom.Material.diffuse);

    const mesh: geom_mesh.Mesh = scene[2].geom.mesh;

    try std.testing.expectEqual(@as(m.Vec3c, .{ 0.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[0]]);
    try std.testing.expectEqual(@as(m.Vec3c, .{ 0.0, 0.0, 1.0 }), mesh.vrt[mesh.ind[1]]);
    try std.testing.expectEqual(@as(m.Vec3c, .{ 0.0, 1.0, 0.0 }), mesh.vrt[mesh.ind[2]]);

    try std.testing.expectEqual(@as(m.Vec3c, .{ 0.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[3]]);
    try std.testing.expectEqual(@as(m.Vec3c, .{ 1.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[4]]);
    try std.testing.expectEqual(@as(m.Vec3c, .{ 0.0, 0.0, 1.0 }), mesh.vrt[mesh.ind[5]]);

    try std.testing.expectEqual(@as(m.Vec3c, .{ 0.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[6]]);
    try std.testing.expectEqual(@as(m.Vec3c, .{ 0.0, 1.0, 0.0 }), mesh.vrt[mesh.ind[7]]);
    try std.testing.expectEqual(@as(m.Vec3c, .{ 1.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[8]]);

    try std.testing.expectEqual(@as(m.Vec3c, .{ 1.0, 0.0, 0.0 }), mesh.vrt[mesh.ind[9]]);
    try std.testing.expectEqual(@as(m.Vec3c, .{ 0.0, 0.0, 1.0 }), mesh.vrt[mesh.ind[10]]);
    try std.testing.expectEqual(@as(m.Vec3c, .{ 0.0, 1.0, 0.0 }), mesh.vrt[mesh.ind[11]]);

    try std.testing.expectEqual(scene[2].trfm, @as(m.Mat4, .{
        .{ 1.0, 0.0, 0.0, 0.0 },
        .{ 0.0, 1.0, 0.0, 0.0 },
        .{ 0.0, 0.0, 1.0, 0.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
    }));
    try std.testing.expectEqual(scene[2].refl, @as(m.Vec3, .{ 1.0, 1.0, 1.0 }));
    try std.testing.expectEqual(scene[2].emit, @as(m.Vec3, .{ 0.0, 0.0, 0.0 }));
    try std.testing.expectEqual(scene[2].mtrl, geom.Material.diffuse);
}

pub fn fmtComma(value: anytype) CommaFormatter(@TypeOf(value)) {
    const info = @typeInfo(@TypeOf(value));
    if (info != .int and info != .comptime_int) {
        @compileError("integer type required for comma formatting, got " ++ @typeName(@TypeOf(value)));
    }

    return .{ .value = value };
}

fn CommaFormatter(comptime T: type) type {
    return struct {
        value: T,

        pub fn format(self: @This(), writer: *std.Io.Writer) !void {
            if (self.value == 0) { // this check is necessary due to exit condition of loop below
                try writer.writeByte('0');
                return;
            }
            if (self.value < 0) try writer.writeByte('-');
            var val: u64 = @intCast(@abs(self.value));
            var buf: [32]u8 = undefined; // note 10^20 > 2^64
            var len: usize = 0;
            while (val > 0) : (len += 1) {
                buf[len] = @intCast(@mod(val, 10) + '0');
                val = @divTrunc(val, 10);
            }
            var i: usize = 0;
            while (i < len) : (i += 1) {
                if (i > 0 and @mod(len - i, 3) == 0) try writer.writeByte(',');
                try writer.writeByte(buf[len - 1 - i]);
            }
        }
    };
}
