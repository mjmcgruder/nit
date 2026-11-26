const std = @import("std");

pub const StdOut = struct {
    file_writer: std.Io.File.Writer,
    pub fn init(stdio: std.Io) StdOut {
        return .{ .file_writer = std.Io.File.stdout().writer(stdio, &.{}) };
    }
    pub fn print(stdout: *StdOut, comptime fmt: []const u8, args: anytype) !void {
        const writer: *std.Io.Writer = &stdout.file_writer.interface;
        try writer.print(fmt, args);
    }
};

pub fn duration(start: std.Io.Timestamp, stop: std.Io.Timestamp) f64 {
    const dur: f64 = @floatFromInt(start.durationTo(stop).nanoseconds);
    const div: f64 = @floatFromInt(std.time.ns_per_s);
    return dur / div;
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
