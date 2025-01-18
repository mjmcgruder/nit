const std = @import("std");

pub fn trimWhitespace(str: []u8) []u8 {
    var begin: usize = 0;
    while (begin < str.len and std.ascii.isWhitespace(str[begin])) : (begin += 1) {}
    var end: usize = begin + 1;
    while (end < str.len and !std.ascii.isWhitespace(str[end])) : (end += 1) {}
    return str[begin..end];
}

pub fn readInput(file_name: []const u8) !void {
    const cwd: std.fs.Dir = std.fs.cwd();
    const fID: std.fs.File = try cwd.openFile(file_name, .{});
    defer fID.close();

    var read_buffer: [1 << 10]u8 = undefined;
    while (try fID.reader().readUntilDelimiterOrEof(&read_buffer, '\n')) |line_buffer| {
        var key: []u8 = undefined;
        var val: []u8 = undefined;
        var split: usize = 0;
        while (split < line_buffer.len) : (split += 1) {
            if (line_buffer[split] == '=') {
                key = line_buffer[0..split];
                val = line_buffer[(split + 1)..];
                break;
            }
        }
        key = trimWhitespace(key);
        val = trimWhitespace(val);
        std.debug.print("key: {s} val: {s}\n", .{ key, val });
    }
}

pub fn main() !void {
    try readInput("test_input.txt");
}
