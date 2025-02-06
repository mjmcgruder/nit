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
    inline for (@typeInfo(enum_type).Enum.fields) |field| {
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
    inline for (@typeInfo(@TypeOf(settings)).Struct.fields) |field| {
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

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var settings: Settings = Settings{};
    var scene_list: std.ArrayList(geom.Object) = std.ArrayList(geom.Object).init(arena);
    defer scene_list.deinit(); // deinit and arena allocator?
    try readInput("test_input.txt", &settings, &scene_list);

    stdout.print("{}\n", .{settings.max_bounces});
    stdout.print("{}\n", .{settings.num_samples});
    stdout.print("{}\n", .{settings.window_w});
    stdout.print("{}\n", .{settings.window_h});
    stdout.print("{d} {d} {d}\n", .{ settings.camera_position.x, settings.camera_position.y, settings.camera_position.z });
    stdout.print("{d} {d} {d}\n", .{ settings.target_position.x, settings.target_position.y, settings.target_position.z });

    stdout.print("SPHERES LEN: {}\n", .{scene_list.items.len});
    for (scene_list.items, 0..) |object, i| {
        stdout.print("sphere {}\n", .{i});
        stdout.print("  center:      {} {} {}\n", .{ object.c.x, object.c.y, object.c.z });
        stdout.print("  radius:      {}\n", .{object.r});
        stdout.print("  reflectance: {} {} {}\n", .{ object.refl.x, object.refl.y, object.refl.z });
        stdout.print("  emittance:   {} {} {}\n", .{ object.emit.x, object.emit.y, object.emit.z });
        stdout.print("  material:    {}\n", .{object.mtrl});
    }
}
