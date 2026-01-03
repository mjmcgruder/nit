const std = @import("std");

const m = @import("math.zig");
const geom = @import("geometry.zig");

var stdout_writer = std.fs.File.stdout().writer(&.{});
var stderr_writer = std.fs.File.stderr().writer(&.{});
const stdout = &stdout_writer.interface;
const stderr = &stderr_writer.interface;

pub const Settings = struct {
    thread_count: usize = 8,
    num_samples: usize = 1 << 0,
    window_w: usize = 1920,
    window_h: usize = 1080,
    camera_position: m.Vec3 = m.Vec3{ .data = .{ 0.0, 0.0, 0.0 } },
    target_position: m.Vec3 = m.Vec3{ .data = .{ 1.0, 0.0, 0.0 } },
    up_vector: m.Vec3 = m.Vec3{ .data = .{ 0.0, 1.0, 0.0 } },
    field_of_view: f32 = 90.0,
};

pub const Pixel = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
};

// const ParsingError = error{
//     DelimiterNotFound,
//     KeyNotFound,
//     UnknownBlock,
//     UnknownEnum,
// };
//
// fn parseType(result_type: type, string: []u8) !result_type {
//     return switch (result_type) {
//         usize => try std.fmt.parseInt(usize, string, 10),
//         f32 => try std.fmt.parseFloat(f32, string),
//         m.Vec3 => try parseVector(string),
//         geom.Material => try parseEnum(geom.Material, string),
//         else => comptime unreachable,
//     };
// }
//
// fn parseEnum(enum_type: type, string: []u8) !enum_type {
//     inline for (@typeInfo(enum_type).@"enum".fields) |field| {
//         if (std.mem.eql(u8, string, field.name)) {
//             return @field(enum_type, field.name);
//         }
//     }
//     return ParsingError.UnknownEnum;
// }
// fn setSetting(key: []u8, val: []u8, settings: anytype) !@TypeOf(settings) {
//     var new_settings = settings;
//     inline for (@typeInfo(@TypeOf(settings)).@"struct".fields) |field| {
//         if (std.mem.eql(u8, key, field.name)) {
//             @field(new_settings, field.name) = try parseType(field.type, val);
//             return new_settings;
//         }
//     }
//     return ParsingError.KeyNotFound;
// }
//
// fn trimWhitespace(str: []u8) []u8 {
//     var start: usize = 0;
//     while (start < str.len and std.ascii.isWhitespace(str[start])) : (start += 1) {}
//     var end: usize = str.len;
//     while (end > start and std.ascii.isWhitespace(str[end - 1])) : (end -= 1) {}
//     return str[start..end];
// }
//
// fn splitAtDelimiter(str: []u8, delim: u8) ParsingError![2][]u8 {
//     var output: [2][]u8 = undefined;
//     var split: usize = 0;
//     var delimiter_found: bool = false;
//     while (split < str.len) : (split += 1) {
//         if (str[split] == delim) {
//             output[0] = str[0..split];
//             output[1] = str[(split + 1)..];
//             delimiter_found = true;
//             break;
//         }
//     }
//     return if (delimiter_found) output else ParsingError.DelimiterNotFound;
// }
//
// pub fn readInput(
//     allocator: std.mem.Allocator,
//     file_name: []const u8,
//     settings: *Settings,
//     scene: *std.ArrayList(geom.Object),
// ) !void {
//     const ParseMode = enum {
//         normal,
//         sphere,
//     };
//
//     var mode: ParseMode = ParseMode.normal;
//
//     const cwd: std.fs.Dir = std.fs.cwd();
//     const fID: std.fs.File = try cwd.openFile(file_name, .{});
//     defer fID.close();
//
//     var read_buffer: [1 << 12]u8 = undefined;
//     var file_reader = fID.reader(&read_buffer);
//     const reader = &file_reader.interface;
//
//     var line_num: usize = 1;
//     var next_line_normal: bool = false;
//     while (reader.takeDelimiterExclusive('\n')) |line| : (line_num += 1) {
//         reader.toss(1); // pass the newline character
//         errdefer stderr.print("parsing error at line {}\n", .{line_num}) catch unreachable;
//
//         if (next_line_normal == true) {
//             mode = ParseMode.normal;
//             next_line_normal = false;
//         }
//
//         // trim comments and extra white space
//         var segment: []u8 = trimWhitespace(
//             (splitAtDelimiter(line, '#') catch [2][]u8{ line, line })[0],
//         );
//         if (segment.len == 0) continue;
//
//         // determine mode change (mode change is always followed by "continue;")
//         if (mode == ParseMode.normal) {
//             if (splitAtDelimiter(segment, '{')) |mode_string_dual| {
//                 mode = try parseEnum(ParseMode, trimWhitespace(mode_string_dual[0]));
//                 try scene.append(allocator, geom.Object{});
//                 continue;
//             } else |_| {}
//         } else {
//             if (splitAtDelimiter(segment, '}')) |close_string_dual| {
//                 segment = trimWhitespace(close_string_dual[0]);
//                 next_line_normal = true;
//             } else |_| {}
//         }
//
//         if (segment.len == 0) continue;
//
//         // parse key-value pair
//         const keyval: [2][]u8 = try splitAtDelimiter(segment, '=');
//         const key: []u8 = trimWhitespace(keyval[0]);
//         const val: []u8 = trimWhitespace(keyval[1]);
//
//         // assign settings
//         switch (mode) {
//             ParseMode.normal => {
//                 settings.* = try setSetting(key, val, settings.*);
//             },
//             ParseMode.sphere => {
//                 const last_object: *geom.Object = &scene.items[scene.items.len - 1];
//                 last_object.* = try setSetting(key, val, last_object.*);
//             },
//         }
//     } else |_| {}
// }

pub fn writeImage(frame_buffer: []const Pixel, settings: Settings, file_name: []const u8) !void {
    const file: std.fs.File = try std.fs.cwd().createFile(file_name, .{});
    defer file.close();

    var write_buffer: [1 << 12]u8 = undefined;
    var file_writer = file.writer(&write_buffer);
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
};

fn seekWhitespace(str: []u8, start: usize) usize {
    var head: usize = start;
    while (head < str.len and !std.ascii.isWhitespace(str[head])) : (head += 1) {}
    return head;
}
fn seekPastWhitespace(str: []u8, start: usize) usize {
    var head: usize = start;
    while (head < str.len and std.ascii.isWhitespace(str[head])) : (head += 1) {}
    return head;
}
fn seekCharacter(str: []u8, start: usize, char: u8) usize {
    var head: usize = start;
    while (head < str.len and str[head] != char) : (head += 1) {}
    return head;
}
fn seekNext(str: []u8, start: usize) usize {
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

fn parseEnum(enum_type: type, string: []u8) !enum_type {
    inline for (@typeInfo(enum_type).@"enum".fields) |field| {
        if (std.mem.eql(u8, string, field.name)) {
            return @field(enum_type, field.name);
        }
    }
    return ParsingError.UnknownEnumValue;
}

fn parseVec3(str: []u8) !m.Vec3 {
    const begin_elem0 = seekPastWhitespace(str, 0);
    const end_elem0 = seekCharacter(str, begin_elem0, ',');
    const elem0: []u8 = str[begin_elem0..end_elem0];
    if (elem0.len == 0) return ParsingError.FormatError;
    const begin_elem1 = seekNext(str, end_elem0);
    const end_elem1 = seekCharacter(str, begin_elem1, ',');
    const elem1: []u8 = str[begin_elem1..end_elem1];
    if (elem1.len == 0) return ParsingError.FormatError;
    const begin_elem2 = seekNext(str, end_elem1);
    const end_elem2 = seekWhitespace(str, begin_elem2);
    const elem2: []u8 = str[begin_elem2..end_elem2];
    if (elem2.len == 0) return ParsingError.FormatError;
    return m.Vec3{ .data = .{
        try std.fmt.parseFloat(f32, elem0),
        try std.fmt.parseFloat(f32, elem1),
        try std.fmt.parseFloat(f32, elem2),
    } };
}

fn parseVec4(str: []u8) !m.Vec4 {
    const begin_elem0 = seekPastWhitespace(str, 0);
    const end_elem0 = seekCharacter(str, begin_elem0, ',');
    const elem0: []u8 = str[begin_elem0..end_elem0];
    if (elem0.len == 0) return ParsingError.FormatError;
    const begin_elem1 = seekNext(str, end_elem0);
    const end_elem1 = seekCharacter(str, begin_elem1, ',');
    const elem1: []u8 = str[begin_elem1..end_elem1];
    if (elem1.len == 0) return ParsingError.FormatError;
    const begin_elem2 = seekNext(str, end_elem1);
    const end_elem2 = seekCharacter(str, begin_elem2, ',');
    const elem2: []u8 = str[begin_elem2..end_elem2];
    if (elem2.len == 0) return ParsingError.FormatError;
    const begin_elem3 = seekNext(str, end_elem2);
    const end_elem3 = seekWhitespace(str, begin_elem3);
    const elem3: []u8 = str[begin_elem3..end_elem3];
    if (elem3.len == 0) return ParsingError.FormatError;
    return m.Vec4{ .data = .{
        try std.fmt.parseFloat(f32, elem0),
        try std.fmt.parseFloat(f32, elem1),
        try std.fmt.parseFloat(f32, elem2),
        try std.fmt.parseFloat(f32, elem3),
    } };
}

const InputParseMode = enum {
    normal,
    object,
};

pub fn readInput(
    rel_path: []const u8,
    allocator: std.mem.Allocator,
) !struct { settings: Settings, scene: std.ArrayList(geom.Object) } {
    var settings: Settings = .{};
    var scene: std.ArrayList(geom.Object) = .empty;

    var mode: InputParseMode = .normal;

    const fID: std.fs.File = try std.fs.cwd().openFile(rel_path, .{});
    defer fID.close();

    var read_buffer: [1 << 12]u8 = undefined;
    var file_reader = fID.reader(&read_buffer);
    const reader = &file_reader.interface;

    var line_num: usize = 1;
    var trim: []u8 = &.{};
    var word: []u8 = &.{};

    line_loop: while (reader.takeDelimiterInclusive('\n')) |line| : (line_num += 1) {
        errdefer stderr.print("parsing error at line {}\n", .{line_num}) catch unreachable;

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

            if (std.mem.eql(u8, word, "sphere")) {
                try scene.append(allocator, .{ .geom = geom.GeometryType{ .sphere = .{} } });
                continue :line_loop;
            } else if (std.mem.eql(u8, word, "box")) {
                try scene.append(allocator, .{ .geom = geom.GeometryType{ .box = .{} } });
                continue :line_loop;
            } else if (std.mem.eql(u8, word, "mesh")) {
                try scene.append(allocator, .{ .geom = geom.GeometryType{ .mesh = .{} } });
                continue :line_loop;
            }

            // inline for (@typeInfo(geom.GeometryType).@"enum".fields) |field| {
            //     if (std.mem.eql(u8, word, field.name)) {
            //         // object_type = @field(geom.GeometryType, field.name);
            //         scene.append(allocator, .{});
            //         continue :line_loop;
            //     }
            // }

            return ParsingError.UnknownObjectType;
        }

        // parse key-value pairs
        var key: []u8 = &.{};
        var val: []u8 = &.{};
        try parseKeyVal(trim, &key, &val);
        std.debug.print("{}: {s} {s}\n", .{ mode, key, val });

        // assign info
        switch (mode) {
            .normal => {
                if (std.mem.eql(u8, key, "num_threads")) {
                    settings.thread_count = try std.fmt.parseInt(usize, val, 10);
                } else if (std.mem.eql(u8, key, "num_samples")) {
                    settings.num_samples = try std.fmt.parseInt(usize, val, 10);
                } else if (std.mem.eql(u8, key, "window_width")) {
                    settings.window_w = try std.fmt.parseInt(usize, val, 10);
                } else if (std.mem.eql(u8, key, "window_height")) {
                    settings.window_h = try std.fmt.parseInt(usize, val, 10);
                } else if (std.mem.eql(u8, key, "camera_position")) {
                    settings.camera_position = try parseVec3(val);
                } else if (std.mem.eql(u8, key, "target_position")) {
                    settings.target_position = try parseVec3(val);
                } else if (std.mem.eql(u8, key, "up_vector")) {
                    settings.up_vector = try parseVec3(val);
                } else if (std.mem.eql(u8, key, "horizontal_fov")) {
                    settings.field_of_view = try std.fmt.parseFloat(f32, val);
                } else {
                    return ParsingError.UnknownKey;
                }
            },
            .object => {
                var object: *geom.Object = &scene.items[scene.items.len - 1];

                if (std.mem.eql(u8, key, "geom")) {
                    switch (object.geom) {
                        .sphere => |*value| value.*.r = try std.fmt.parseFloat(f32, val),
                        .box => |*value| value.*.size = try parseVec3(val),
                        .mesh => |*value| value.* = try readASCIISTL(val, allocator),
                    }
                } else if (std.mem.eql(u8, key, "scale")) {
                    const scale: f32 = try std.fmt.parseFloat(f32, val);
                    object.trfm = m.matmul4(m.scale(scale), object.trfm);
                } else if (std.mem.eql(u8, key, "rotate")) {
                    const r = (try parseVec4(val)).data;
                    object.trfm = m.matmul4(m.rotateAboutAxis(.{ .data = .{ r[0], r[1], r[2] } }, r[3]), object.trfm);
                } else if (std.mem.eql(u8, key, "translate")) {
                    const t = (try parseVec3(val));
                    object.trfm = m.matmul4(m.translate(t), object.trfm);
                } else if (std.mem.eql(u8, key, "refl")) {
                    object.refl = try parseVec3(val);
                } else if (std.mem.eql(u8, key, "emit")) {
                    object.emit = try parseVec3(val);
                } else if (std.mem.eql(u8, key, "mtrl")) {
                    object.mtrl = try parseEnum(geom.Material, val);
                } else {
                    return ParsingError.UnknownKey;
                }
            },
        }
    } else |_| {} // end of file

    return .{ .settings = settings, .scene = scene };
}

const STLReadError = error{ // TODO: possibly generalize this
    FormatError,
    FacetLimitExceeded,
};

pub fn readASCIISTL(
    rel_path: []const u8,
    allocator: std.mem.Allocator,
) !geom.Mesh {
    var result: geom.Mesh = .{};

    const fID: std.fs.File = try std.fs.cwd().openFile(rel_path, .{});
    defer fID.close();

    var read_buffer: [1 << 12]u8 = undefined;
    var file_reader = fID.reader(&read_buffer);
    const reader = &file_reader.interface;

    var trim: []u8 = undefined;
    var word: []u8 = undefined;

    trim = try reader.takeDelimiterInclusive('\n');
    trim = getNextWord(trim, &word);
    if (!std.mem.eql(u8, word, "solid")) return STLReadError.FormatError;

    for (0..(1 << 27)) |_| {
        trim = try reader.takeDelimiterInclusive('\n');
        trim = getNextWord(trim, &word);
        if (std.mem.eql(u8, word, "endsolid")) return result;
        if (!std.mem.eql(u8, word, "facet")) return STLReadError.FormatError;
        trim = getNextWord(trim, &word);
        if (!std.mem.eql(u8, word, "normal")) return STLReadError.FormatError;

        trim = try reader.takeDelimiterInclusive('\n');
        trim = getNextWord(trim, &word);
        if (!std.mem.eql(u8, word, "outer")) return STLReadError.FormatError;
        trim = getNextWord(trim, &word);
        if (!std.mem.eql(u8, word, "loop")) return STLReadError.FormatError;

        for (0..3) |_| {
            trim = try reader.takeDelimiterInclusive('\n');
            trim = getNextWord(trim, &word);
            if (!std.mem.eql(u8, word, "vertex")) return STLReadError.FormatError;
            var vertex: m.Vec3 = .{};
            for (0..3) |i| {
                trim = getNextWord(trim, &word);
                vertex.data[i] = try std.fmt.parseFloat(f32, word);
            }
            try result.vrt.append(allocator, vertex);
            try result.ind.append(allocator, @as(u32, @intCast(result.ind.items.len))); // TODO: fails if too many indices
        }

        trim = try reader.takeDelimiterInclusive('\n');
        trim = getNextWord(trim, &word);
        if (!std.mem.eql(u8, word, "endloop")) return STLReadError.FormatError;

        trim = try reader.takeDelimiterInclusive('\n');
        trim = getNextWord(trim, &word);
        if (!std.mem.eql(u8, word, "endfacet")) return STLReadError.FormatError;
    }

    return STLReadError.FacetLimitExceeded;
}

// TESTS -----

test "readASCIISTL --- runs" {
    const allocator: std.mem.Allocator = std.testing.allocator;
    var mesh: geom.Mesh = try readASCIISTL("Suzanne.stl", allocator);
    defer mesh.deinit(allocator);

    for (0..(mesh.ind.items.len / 3)) |ti| {
        const v0: m.Vec3 = mesh.vrt.items[mesh.ind.items[3 * ti + 0]];
        const v1: m.Vec3 = mesh.vrt.items[mesh.ind.items[3 * ti + 1]];
        const v2: m.Vec3 = mesh.vrt.items[mesh.ind.items[3 * ti + 2]];
        std.debug.print("{} {} {}\n", .{ v0.data[0], v0.data[1], v0.data[2] });
        std.debug.print("{} {} {}\n", .{ v1.data[0], v1.data[1], v1.data[2] });
        std.debug.print("{} {} {}\n", .{ v2.data[0], v2.data[1], v2.data[2] });
        std.debug.print("\n", .{});
    }
}

test "readInput --- runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const allocator: std.mem.Allocator = arena.allocator();

    _ = try readInput("input_test.txt", allocator);
}

// test "readInput --- reads an input file" {
//     var settings = Settings{};
//     var scene_list = std.ArrayList(geom.Object).empty;
//     try readInput(std.testing.allocator, "test_data/input.txt", &settings, &scene_list);
//     const scene: []geom.Object = scene_list.items;
//     defer scene_list.deinit(std.testing.allocator);
//
//     try std.testing.expectEqual(16, settings.thread_count);
//     try std.testing.expectEqual(8192, settings.num_samples);
//     try std.testing.expectEqual(1920, settings.window_w);
//     try std.testing.expectEqual(1080, settings.window_h);
//     try std.testing.expectEqual(1.2, settings.camera_position.data[0]);
//     try std.testing.expectEqual(-0.1, settings.camera_position.data[1]);
//     try std.testing.expectEqual(-0.4, settings.camera_position.data[2]);
//     try std.testing.expectEqual(1.2, settings.target_position.data[0]);
//     try std.testing.expectEqual(-0.1, settings.target_position.data[1]);
//     try std.testing.expectEqual(0.5, settings.target_position.data[2]);
//     try std.testing.expectEqual(0.0, settings.up_vector.data[0]);
//     try std.testing.expectEqual(1.0, settings.up_vector.data[1]);
//     try std.testing.expectEqual(0.0, settings.up_vector.data[2]);
//     try std.testing.expectEqual(90.0, settings.field_of_view);
//
//     try std.testing.expectApproxEqRel(1.4, scene[0].cntr.data[0], 4 * m.eps);
//     try std.testing.expectApproxEqRel(0.0, scene[0].cntr.data[1], 4 * m.eps);
//     try std.testing.expectApproxEqRel(-0.4, scene[0].cntr.data[2], 4 * m.eps);
//     try std.testing.expectApproxEqRel(0.1, scene[0].rdus, 4 * m.eps);
//     try std.testing.expectApproxEqRel(1.0, scene[0].refl.data[0], 4 * m.eps);
//     try std.testing.expectApproxEqRel(1.0, scene[0].refl.data[1], 4 * m.eps);
//     try std.testing.expectApproxEqRel(1.0, scene[0].refl.data[2], 4 * m.eps);
//     try std.testing.expectApproxEqRel(12.0, scene[0].emit.data[0], 4 * m.eps);
//     try std.testing.expectApproxEqRel(12.0, scene[0].emit.data[1], 4 * m.eps);
//     try std.testing.expectApproxEqRel(12.0, scene[0].emit.data[2], 4 * m.eps);
//     try std.testing.expectEqual(geom.Material.diffuse, scene[0].mtrl);
//
//     try std.testing.expectApproxEqRel(1.0, scene[1].cntr.data[0], 4 * m.eps);
//     try std.testing.expectApproxEqRel(0.0, scene[1].cntr.data[1], 4 * m.eps);
//     try std.testing.expectApproxEqRel(1000.5, scene[1].cntr.data[2], 4 * m.eps);
//     try std.testing.expectApproxEqRel(1000.0, scene[1].rdus, 4 * m.eps);
//     try std.testing.expectApproxEqRel(0.8, scene[1].refl.data[0], 4 * m.eps);
//     try std.testing.expectApproxEqRel(0.2, scene[1].refl.data[1], 4 * m.eps);
//     try std.testing.expectApproxEqRel(0.2, scene[1].refl.data[2], 4 * m.eps);
//     try std.testing.expectApproxEqRel(0.0, scene[1].emit.data[0], 4 * m.eps);
//     try std.testing.expectApproxEqRel(0.0, scene[1].emit.data[1], 4 * m.eps);
//     try std.testing.expectApproxEqRel(0.0, scene[1].emit.data[2], 4 * m.eps);
//     try std.testing.expectEqual(geom.Material.specular, scene[1].mtrl);
// }
