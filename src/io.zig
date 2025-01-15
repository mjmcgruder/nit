const std = @import("std");

pub fn readInput(file_name: []const u8) !void {
    const cwd: std.fs.Dir = std.fs.cwd();
    const fID: std.fs.File = try cwd.openFile(file_name, .{});
    defer fID.close();

    var read_buffer: [1 << 10]u8 = undefined;
    while (try fID.reader().readUntilDelimiterOrEof(&read_buffer, '\n')) |line_buffer| {
        std.debug.print("{s}\n", .{line_buffer});
    }
}

pub fn main() !void {
    try readInput("test_input.txt");
}
