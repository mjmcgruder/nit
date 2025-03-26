const std = @import("std");

const m = @import("math.zig");
const geom = @import("geometry.zig");

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub const Settings = struct {
    thread_count: usize = 1,
    num_samples: usize = 32,
    window_w: usize = 1920,
    window_h: usize = 1080,
    camera_position: m.Vec3 = m.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    target_position: m.Vec3 = m.Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
    up_vector: m.Vec3 = m.Vec3{ .x = 0.0, .y = 1.0, .z = 0.0 },
    field_of_view: f32 = 90.0,
};

pub const Pixel = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

const ParsingError = error{
    DelimiterNotFound,
    KeyNotFound,
    UnknownBlock,
    UnknownEnum,
};

fn parseType(result_type: type, string: []u8) !result_type {
    return switch (result_type) {
        usize => try std.fmt.parseInt(usize, string, 10),
        f32 => try std.fmt.parseFloat(f32, string),
        m.Vec3 => try parseVector(string),
        geom.Material => try parseEnum(geom.Material, string),
        else => comptime unreachable,
    };
}

fn parseEnum(enum_type: type, string: []u8) !enum_type {
    inline for (@typeInfo(enum_type).@"enum".fields) |field| {
        if (std.mem.eql(u8, string, field.name)) {
            return @field(enum_type, field.name);
        }
    }
    return ParsingError.UnknownEnum;
}

fn parseVector(string: []u8) !m.Vec3 {
    const split0: [2][]u8 = try splitAtDelimiter(string, ',');
    const split1: [2][]u8 = try splitAtDelimiter(split0[1], ',');
    return m.Vec3{
        .x = try std.fmt.parseFloat(f32, split0[0]),
        .y = try std.fmt.parseFloat(f32, split1[0]),
        .z = try std.fmt.parseFloat(f32, split1[1]),
    };
}

fn setSetting(key: []u8, val: []u8, settings: anytype) !@TypeOf(settings) {
    var new_settings = settings;
    inline for (@typeInfo(@TypeOf(settings)).@"struct".fields) |field| {
        if (std.mem.eql(u8, key, field.name)) {
            @field(new_settings, field.name) = try parseType(field.type, val);
            return new_settings;
        }
    }
    return ParsingError.KeyNotFound;
}

fn trimWhitespace(str: []u8) []u8 {
    var start: usize = 0;
    while (start < str.len and std.ascii.isWhitespace(str[start])) : (start += 1) {}
    var end: usize = str.len;
    while (end > start and std.ascii.isWhitespace(str[end - 1])) : (end -= 1) {}
    return str[start..end];
}

fn splitAtDelimiter(str: []u8, delim: u8) ParsingError![2][]u8 {
    var output: [2][]u8 = undefined;
    var split: usize = 0;
    var delimiter_found: bool = false;
    while (split < str.len) : (split += 1) {
        if (str[split] == delim) {
            output[0] = str[0..split];
            output[1] = str[(split + 1)..];
            delimiter_found = true;
            break;
        }
    }
    return if (delimiter_found) output else ParsingError.DelimiterNotFound;
}

pub fn readInput(
    file_name: []const u8,
    settings: *Settings,
    scene: *std.ArrayList(geom.Object),
) !void {
    const ParseMode = enum {
        normal,
        sphere,
    };

    var mode: ParseMode = ParseMode.normal;

    const cwd: std.fs.Dir = std.fs.cwd();
    const fID: std.fs.File = try cwd.openFile(file_name, .{});
    defer fID.close();

    var read_buffer: [1 << 10]u8 = undefined;
    var line_num: usize = 1;
    var next_line_normal: bool = false;
    while (try fID.reader().readUntilDelimiterOrEof(&read_buffer, '\n')) |line| : (line_num += 1) {
        errdefer stderr.print("parsing error at line {}\n", .{line_num}) catch unreachable;

        if (next_line_normal == true) {
            mode = ParseMode.normal;
            next_line_normal = false;
        }

        // trim comments and extra white space
        var segment: []u8 = trimWhitespace(
            (splitAtDelimiter(line, '#') catch [2][]u8{ line, line })[0],
        );
        if (segment.len == 0) continue;

        // determine mode change (mode change is always followed by "continue;")
        if (mode == ParseMode.normal) {
            if (splitAtDelimiter(segment, '{')) |mode_string_dual| {
                mode = try parseEnum(ParseMode, trimWhitespace(mode_string_dual[0]));
                try scene.append(geom.Object{});
                continue;
            } else |_| {}
        } else {
            if (splitAtDelimiter(segment, '}')) |close_string_dual| {
                segment = trimWhitespace(close_string_dual[0]);
                next_line_normal = true;
            } else |_| {}
        }

        if (segment.len == 0) continue;

        // parse key-value pair
        const keyval: [2][]u8 = try splitAtDelimiter(segment, '=');
        const key: []u8 = trimWhitespace(keyval[0]);
        const val: []u8 = trimWhitespace(keyval[1]);

        // assign settings
        switch (mode) {
            ParseMode.normal => {
                settings.* = try setSetting(key, val, settings.*);
            },
            ParseMode.sphere => {
                const last_object: *geom.Object = &scene.items[scene.items.len - 1];
                last_object.* = try setSetting(key, val, last_object.*);
            },
        }
    }
}

pub fn writeImage(frame_buffer: []const Pixel, settings: Settings, file_name: []const u8) !void {
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

// TESTS -----

test "readInput --- reads an input file" {
    var settings = Settings{};
    var scene_list = std.ArrayList(geom.Object).init(std.testing.allocator);
    try readInput("test_data/input.txt", &settings, &scene_list);
    const scene: []geom.Object = scene_list.items;
    defer scene_list.deinit();

    try std.testing.expectEqual(16, settings.thread_count);
    try std.testing.expectEqual(8192, settings.num_samples);
    try std.testing.expectEqual(1920, settings.window_w);
    try std.testing.expectEqual(1080, settings.window_h);
    try std.testing.expectEqual(1.2, settings.camera_position.x);
    try std.testing.expectEqual(-0.1, settings.camera_position.y);
    try std.testing.expectEqual(-0.4, settings.camera_position.z);
    try std.testing.expectEqual(1.2, settings.target_position.x);
    try std.testing.expectEqual(-0.1, settings.target_position.y);
    try std.testing.expectEqual(0.5, settings.target_position.z);
    try std.testing.expectEqual(0.0, settings.up_vector.x);
    try std.testing.expectEqual(1.0, settings.up_vector.y);
    try std.testing.expectEqual(0.0, settings.up_vector.z);
    try std.testing.expectEqual(90.0, settings.field_of_view);

    try std.testing.expectApproxEqRel(1.4, scene[0].cntr.x, 4 * m.eps);
    try std.testing.expectApproxEqRel(0.0, scene[0].cntr.y, 4 * m.eps);
    try std.testing.expectApproxEqRel(-0.4, scene[0].cntr.z, 4 * m.eps);
    try std.testing.expectApproxEqRel(0.1, scene[0].rdus, 4 * m.eps);
    try std.testing.expectApproxEqRel(1.0, scene[0].refl.x, 4 * m.eps);
    try std.testing.expectApproxEqRel(1.0, scene[0].refl.y, 4 * m.eps);
    try std.testing.expectApproxEqRel(1.0, scene[0].refl.z, 4 * m.eps);
    try std.testing.expectApproxEqRel(12.0, scene[0].emit.x, 4 * m.eps);
    try std.testing.expectApproxEqRel(12.0, scene[0].emit.y, 4 * m.eps);
    try std.testing.expectApproxEqRel(12.0, scene[0].emit.z, 4 * m.eps);
    try std.testing.expectEqual(geom.Material.diffuse, scene[0].mtrl);

    try std.testing.expectApproxEqRel(1.0, scene[1].cntr.x, 4 * m.eps);
    try std.testing.expectApproxEqRel(0.0, scene[1].cntr.y, 4 * m.eps);
    try std.testing.expectApproxEqRel(1000.5, scene[1].cntr.z, 4 * m.eps);
    try std.testing.expectApproxEqRel(1000.0, scene[1].rdus, 4 * m.eps);
    try std.testing.expectApproxEqRel(0.8, scene[1].refl.x, 4 * m.eps);
    try std.testing.expectApproxEqRel(0.2, scene[1].refl.y, 4 * m.eps);
    try std.testing.expectApproxEqRel(0.2, scene[1].refl.z, 4 * m.eps);
    try std.testing.expectApproxEqRel(0.0, scene[1].emit.x, 4 * m.eps);
    try std.testing.expectApproxEqRel(0.0, scene[1].emit.y, 4 * m.eps);
    try std.testing.expectApproxEqRel(0.0, scene[1].emit.z, 4 * m.eps);
    try std.testing.expectEqual(geom.Material.specular, scene[1].mtrl);
}
