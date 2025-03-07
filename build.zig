const std = @import("std");

pub fn build(b: *std.Build) !void {
    const options_target = b.standardTargetOptions(.{});
    const options_optimization = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "metropolis",
        .root_source_file = b.path("metropolis.zig"),
        .target = options_target,
        .optimize = options_optimization,
    });
    b.installArtifact(exe);

    const unit_tests = b.addTest(.{
        .name = "test",
        .root_source_file = b.path("metropolis.zig"),
        .target = options_target,
        .optimize = options_optimization,
    });
    b.installArtifact(unit_tests);
}
