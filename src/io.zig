const std = @import("std");
const mth = @import("math.zig");

const ParsingError = error{
    DelimiterNotFound,
    KeyNotFound,
};

const Settings = struct {
    max_bounces: usize = 8,
    num_samples: usize = 32,
    window_w: usize = 1920,
    window_h: usize = 1080,
    camera_position: mth.Vec3 = mth.Vec3{ .x = 0.0, .y = 0.0, .z = 0.0 },
    target_position: mth.Vec3 = mth.Vec3{ .x = 1.0, .y = 1.0, .z = 1.0 },
};

fn setSetting(key: []u8, val: []u8, settings: *Settings) !void {
    if (std.mem.eql(u8, key, "max_bounces")) {
        settings.max_bounces = try std.fmt.parseInt(usize, val, 10);
    } else if (std.mem.eql(u8, key, "num_samples")) {
        settings.num_samples = try std.fmt.parseInt(usize, val, 10);
    } else if (std.mem.eql(u8, key, "window_w")) {
        settings.window_w = try std.fmt.parseInt(usize, val, 10);
    } else if (std.mem.eql(u8, key, "window_h")) {
        settings.window_h = try std.fmt.parseInt(usize, val, 10);
    } else if (std.mem.eql(u8, key, "camera_position")) {
        settings.camera_position = try parseVector(val);
    } else if (std.mem.eql(u8, key, "target_position")) {
        settings.target_position = try parseVector(val);
    } else {
        return ParsingError.KeyNotFound;
    }
}

fn parseVector(str: []u8) !mth.Vec3 {
    const split0: [2][]u8 = try splitAtDelimiter(str, ',');
    const split1: [2][]u8 = try splitAtDelimiter(split0[1], ',');
    return mth.Vec3{
        .x = try std.fmt.parseFloat(f32, split0[0]),
        .y = try std.fmt.parseFloat(f32, split1[0]),
        .z = try std.fmt.parseFloat(f32, split1[1]),
    };
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

pub fn readInput(file_name: []const u8) !Settings {
    var settings: Settings = Settings{};

    const cwd: std.fs.Dir = std.fs.cwd();
    const fID: std.fs.File = try cwd.openFile(file_name, .{});
    defer fID.close();

    var read_buffer: [1 << 10]u8 = undefined;
    while (try fID.reader().readUntilDelimiterOrEof(&read_buffer, '\n')) |line| {
        // trim comments and extra white space
        const parse: []u8 = trimWhitespace(
            (splitAtDelimiter(line, '#') catch [2][]u8{ line, line })[0],
        );
        if (parse.len == 0) continue;

        // parse key-value pair
        const keyval: [2][]u8 = try splitAtDelimiter(parse, '=');
        const key: []u8 = trimWhitespace(keyval[0]);
        const val: []u8 = trimWhitespace(keyval[1]);

        // assign settings
        try setSetting(key, val, &settings);
    }

    return settings;
}

pub fn main() !void {
    const settings: Settings = try readInput("test_input.txt");
    std.debug.print("{}\n", .{settings.max_bounces});
    std.debug.print("{}\n", .{settings.num_samples});
    std.debug.print("{}\n", .{settings.window_w});
    std.debug.print("{}\n", .{settings.window_h});
    std.debug.print("{d} {d} {d}\n", .{ settings.camera_position.x, settings.camera_position.y, settings.camera_position.z });
    std.debug.print("{d} {d} {d}\n", .{ settings.target_position.x, settings.target_position.y, settings.target_position.z });
}
