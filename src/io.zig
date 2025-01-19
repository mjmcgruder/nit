const std = @import("std");
const mth = @import("math.zig");
const geom = @import("geometry.zig");

const ParsingError = error{
    DelimiterNotFound,
    KeyNotFound,
    UnknownBlock,
    UnknownEnum,
};

const Settings = struct {
    max_bounces: usize = 8,
    num_samples: usize = 32,
    window_w: usize = 1920,
    window_h: usize = 1080,
    camera_position: mth.Vec3 = mth.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    target_position: mth.Vec3 = mth.Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
};

fn parseType(result_type: type, string: []u8) !result_type {
    return switch (result_type) {
        usize => try std.fmt.parseInt(usize, string, 10),
        f32 => try std.fmt.parseFloat(f32, string),
        mth.Vec3 => try parseVector(string),
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

fn parseVector(string: []u8) !mth.Vec3 {
    const split0: [2][]u8 = try splitAtDelimiter(string, ',');
    const split1: [2][]u8 = try splitAtDelimiter(split0[1], ',');
    return mth.Vec3{
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

const ParseMode = enum {
    Normal,
    Sphere,
};

pub fn readInput(
    file_name: []const u8,
    settings: *Settings,
    scene: *std.ArrayList(geom.Object),
) !void {
    var mode: ParseMode = ParseMode.Normal;

    const cwd: std.fs.Dir = std.fs.cwd();
    const fID: std.fs.File = try cwd.openFile(file_name, .{});
    defer fID.close();

    var read_buffer: [1 << 10]u8 = undefined;
    while (try fID.reader().readUntilDelimiterOrEof(&read_buffer, '\n')) |line| {
        // trim comments and extra white space
        const segment: []u8 = trimWhitespace(
            (splitAtDelimiter(line, '#') catch [2][]u8{ line, line })[0],
        );
        if (segment.len == 0) continue;

        // determine mode change (mode change is always followed by "continue;")
        if (mode == ParseMode.Normal) {
            if (splitAtDelimiter(segment, '{')) |mode_string_dual| {
                const mode_string: []u8 = trimWhitespace(mode_string_dual[0]);
                if (std.mem.eql(u8, mode_string, "sphere")) {
                    mode = ParseMode.Sphere;
                    try scene.append(geom.Object{});
                } else {
                    return ParsingError.UnknownBlock;
                }
                continue;
            } else |_| {}
        } else {
            if (splitAtDelimiter(segment, '}')) |_| {
                // TODO: ensure '}' is on its own line
                mode = ParseMode.Normal;
                continue;
            } else |_| {}
        }

        // parse key-value pair
        const keyval: [2][]u8 = try splitAtDelimiter(segment, '=');
        const key: []u8 = trimWhitespace(keyval[0]);
        const val: []u8 = trimWhitespace(keyval[1]);

        // assign settings
        switch (mode) {
            ParseMode.Normal => {
                settings.* = try setSetting(key, val, settings.*);
            },
            ParseMode.Sphere => {
                const last_object: *geom.Object = &scene.items[scene.items.len - 1];
                last_object.* = try setSetting(key, val, last_object.*);
            },
        }
    }
}

pub fn main() !void {
    var arena_allocator = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_allocator.deinit();
    const arena = arena_allocator.allocator();

    var settings: Settings = Settings{};
    var scene_list: std.ArrayList(geom.Object) = std.ArrayList(geom.Object).init(arena);
    defer scene_list.deinit(); // deinit and arena allocator?
    try readInput("test_input.txt", &settings, &scene_list);

    std.debug.print("{}\n", .{settings.max_bounces});
    std.debug.print("{}\n", .{settings.num_samples});
    std.debug.print("{}\n", .{settings.window_w});
    std.debug.print("{}\n", .{settings.window_h});
    std.debug.print("{d} {d} {d}\n", .{ settings.camera_position.x, settings.camera_position.y, settings.camera_position.z });
    std.debug.print("{d} {d} {d}\n", .{ settings.target_position.x, settings.target_position.y, settings.target_position.z });

    std.debug.print("SPHERES LEN: {}\n", .{scene_list.items.len});
    for (scene_list.items, 0..) |object, i| {
        std.debug.print("sphere {}\n", .{i});
        std.debug.print("  center:      {} {} {}\n", .{ object.c.x, object.c.y, object.c.z });
        std.debug.print("  radius:      {}\n", .{object.r});
        std.debug.print("  reflectance: {} {} {}\n", .{ object.refl.x, object.refl.y, object.refl.z });
        std.debug.print("  emittance:   {} {} {}\n", .{ object.emit.x, object.emit.y, object.emit.z });
        std.debug.print("  material:    {}\n", .{object.mtrl});
    }
}
