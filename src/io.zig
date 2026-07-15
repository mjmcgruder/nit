const std = @import("std");

const m = @import("math.zig");
const geom = @import("geometry.zig");
const geom_mesh = @import("geometry_mesh.zig");

pub const Settings = struct {
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

fn seekWhitespace(str: []const u8, start: usize) usize {
    var head: usize = start;
    while (head < str.len and !std.ascii.isWhitespace(str[head])) : (head += 1) {}
    return head;
}
fn seekPastWhitespace(str: []const u8, start: usize) usize {
    var head: usize = start;
    while (head < str.len and std.ascii.isWhitespace(str[head])) : (head += 1) {}
    return head;
}
fn seekCharacter(str: []const u8, start: usize, char: u8) usize {
    var head: usize = start;
    while (head < str.len and str[head] != char) : (head += 1) {}
    return head;
}
fn seekNext(str: []const u8, start: usize) usize {
    return if (start + 1 < str.len) start + 1 else start;
}

fn skipWhiteSpace(str: []u8) []u8 {
    return str[seekPastWhitespace(str, 0)..];
}

fn getNextWord(str: []u8, word: *[]u8) []u8 {
    const trim: []u8 = skipWhiteSpace(str);
    const word_end = seekWhitespace(trim, 0);
    word.* = trim[0..word_end];
    return trim[word_end..];
}

fn parseKeyVal(str: []u8, key: *[]u8, val: *[]u8) !void {
    var word: []u8 = &.{};
    var trim: []u8 = str;
    trim = getNextWord(trim, key);
    trim = getNextWord(trim, &word);
    if (!std.mem.eql(u8, word, "=")) return ParsingError.FormatError;
    trim = getNextWord(trim, val);
}

fn parseEnum(enum_type: type, string: []const u8) !enum_type {
    inline for (@typeInfo(enum_type).@"enum".fields) |field| {
        if (std.mem.eql(u8, string, field.name)) {
            return @field(enum_type, field.name);
        }
    }
    return ParsingError.UnknownEnumValue;
}

fn parseVec3(str: []const u8) !m.Vec3 {
    const begin_elem0 = seekPastWhitespace(str, 0);
    const end_elem0 = seekCharacter(str, begin_elem0, ',');
    const elem0: []const u8 = str[begin_elem0..end_elem0];
    if (elem0.len == 0) return ParsingError.FormatError;
    const begin_elem1 = seekNext(str, end_elem0);
    const end_elem1 = seekCharacter(str, begin_elem1, ',');
    const elem1: []const u8 = str[begin_elem1..end_elem1];
    if (elem1.len == 0) return ParsingError.FormatError;
    const begin_elem2 = seekNext(str, end_elem1);
    const end_elem2 = seekWhitespace(str, begin_elem2);
    const elem2: []const u8 = str[begin_elem2..end_elem2];
    if (elem2.len == 0) return ParsingError.FormatError;
    return .{
        try std.fmt.parseFloat(f32, elem0),
        try std.fmt.parseFloat(f32, elem1),
        try std.fmt.parseFloat(f32, elem2),
    };
}

fn parseVec4(str: []const u8) !m.Vec4 {
    const begin_elem0 = seekPastWhitespace(str, 0);
    const end_elem0 = seekCharacter(str, begin_elem0, ',');
    const elem0: []const u8 = str[begin_elem0..end_elem0];
    if (elem0.len == 0) return ParsingError.FormatError;
    const begin_elem1 = seekNext(str, end_elem0);
    const end_elem1 = seekCharacter(str, begin_elem1, ',');
    const elem1: []const u8 = str[begin_elem1..end_elem1];
    if (elem1.len == 0) return ParsingError.FormatError;
    const begin_elem2 = seekNext(str, end_elem1);
    const end_elem2 = seekCharacter(str, begin_elem2, ',');
    const elem2: []const u8 = str[begin_elem2..end_elem2];
    if (elem2.len == 0) return ParsingError.FormatError;
    const begin_elem3 = seekNext(str, end_elem2);
    const end_elem3 = seekWhitespace(str, begin_elem3);
    const elem3: []const u8 = str[begin_elem3..end_elem3];
    if (elem3.len == 0) return ParsingError.FormatError;
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

pub fn readInput(
    rel_path: []const u8,
    alloc_main: std.mem.Allocator,
    alloc_work: std.mem.Allocator,
    io: std.Io,
    stdout: *std.Io.Writer,
) !struct { settings: Settings, scene: std.ArrayList(geom.Object) } {
    try stdout.print("Reading input file \"{s}\".\n", .{rel_path});

    var settings: Settings = .{};
    var scene: std.ArrayList(geom.Object) = .empty;

    var mode: InputParseMode = .normal;

    const fID: std.Io.File = try std.Io.Dir.cwd().openFile(io, rel_path, .{});
    defer fID.close(io);

    var read_buffer: [1 << 12]u8 = undefined;
    var file_reader = fID.reader(io, &read_buffer);
    const reader = &file_reader.interface;

    var line_num: usize = 1;
    var trim: []u8 = &.{};
    var word: []u8 = &.{};

    line_loop: while (reader.takeDelimiterInclusive('\n')) |line| : (line_num += 1) {
        errdefer std.log.err("parsing error at line {}", .{line_num});

        trim = skipWhiteSpace(line);

        // skip comment lines
        if (trim.len == 0 or trim[0] == '#') continue;

        _ = getNextWord(trim, &word);

        // change mode if necessary
        if (std.mem.eql(u8, word, "end")) {
            mode = .normal;
            continue :line_loop;
        }
        if (std.mem.eql(u8, word, "object")) {
            mode = .object;
            trim = getNextWord(trim, &word);
            trim = getNextWord(trim, &word);

            if (geometry_type_map.get(word)) |geom_type| {
                var geometry = geom.GeometryType{ .sphere = .{} };
                switch (geom_type) {
                    .sphere => geometry = geom.GeometryType{ .sphere = .{} },
                    .box => geometry = geom.GeometryType{ .box = .{} },
                    .mesh => geometry = geom.GeometryType{ .mesh = .{} },
                }
                try scene.append(alloc_main, geom.Object{ .geom = geometry });
                continue :line_loop;
            } else {
                return ParsingError.UnknownObjectType;
            }
        }

        // parse key-value pairs
        var key: []u8 = &.{};
        var val: []u8 = &.{};
        try parseKeyVal(trim, &key, &val);

        // assign info
        switch (mode) {
            .normal => {
                if (settings_map.get(key)) |setting| {
                    switch (setting) {
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
                var object: *geom.Object = &scene.items[scene.items.len - 1];

                if (object_map.get(key)) |setting| {
                    var transform: m.Mat4 = m.makeIdentityTransform();

                    switch (setting) {
                        .geometry => {
                            switch (object.geom) {
                                .sphere => |*value| value.*.r = try std.fmt.parseFloat(f32, val),
                                .box => |*value| value.*.size = try parseVec3(val),
                                .mesh => |*value| value.* = blk: {
                                    const raw_mesh = try readASCIISTL(val, alloc_work, io, stdout);
                                    try stdout.print("Deduplicating mesh vertices... ", .{});
                                    const dedupe_start = std.Io.Clock.awake.now(io).nanoseconds;
                                    var mesh = try geom_mesh.deDupeMesh(raw_mesh, alloc_main, alloc_work);
                                    const dedupe_stop = std.Io.Clock.awake.now(io).nanoseconds;
                                    const dedupe_duration = @as(f32, @floatFromInt(dedupe_stop - dedupe_start)) / std.time.ns_per_s;
                                    try stdout.print("done ({f} -> {f} vertices in {d:.3}s).\n", .{ fmtComma(raw_mesh.vrt.len), fmtComma(mesh.vrt.len), dedupe_duration });
                                    try stdout.print("Building BVH for \"{s}\"... ", .{val});
                                    const bvh_build_start = std.Io.Clock.awake.now(io).nanoseconds;
                                    const stats = try geom_mesh.buildBVH(&mesh, alloc_main, 4, 1 << 4);
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
    } else |_| {} // end of file

    for (scene.items) |*obj| {
        obj.itfm = m.invertTransform(obj.trfm);
    }

    return .{ .settings = settings, .scene = scene };
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
    const whitespace: []const u8 = " \t\r\n";

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

    const input = try readInput("src/test_data/input.txt", alloc_main, alloc_work, io, stdout);

    const settings = input.settings;
    try std.testing.expectEqual(settings.thread_count, 8);
    try std.testing.expectEqual(settings.num_samples, 1024);
    try std.testing.expectEqual(settings.window_w, 1920);
    try std.testing.expectEqual(settings.window_h, 1080);
    try std.testing.expectEqual(settings.camera_position, @as(m.Vec3, .{ -2.0, 0.0, 0.0 }));
    try std.testing.expectEqual(settings.target_position, @as(m.Vec3, .{ 0.0, 0.0, 0.0 }));
    try std.testing.expectEqual(settings.up_vector, @as(m.Vec3, .{ 0.0, 1.0, 0.0 }));
    try std.testing.expectEqual(settings.field_of_view, 90.0);

    const scene = input.scene.items;

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

    try std.testing.expectEqual(scene[1].geom.box.size, @as(m.Vec3, .{ 1.0, 1.0, 1.0 }));
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
