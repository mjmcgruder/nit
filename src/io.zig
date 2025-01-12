const std = @import("std");

pub fn readInput(file_name: []const u8) !void {
    const cwd: std.fs.Dir = std.fs.cwd();
    const fID: std.fs.File = cwd.openFile(file_name, .{});
    defer fID.close();
}

pub fn main() !void {
    std.debug.print("hello, it's on...\n", .{});
}
