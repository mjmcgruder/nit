const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target_options = b.standardTargetOptions(.{});
    const optimization_options = b.standardOptimizeOption(.{});

    const use_llvm = if (optimization_options == std.builtin.OptimizeMode.Debug) false else true;

    const exe = b.addExecutable(.{
        .name = "metropolis",
        .root_source_file = b.path("metropolis.zig"),
        .target = target_options,
        .optimize = optimization_options,
        .use_llvm = use_llvm,
    });
    b.installArtifact(exe);

    if (b.option(bool, "build-tests", "Build the test suite") orelse false) {
        const unit_tests = b.addTest(.{
            .name = "test",
            .root_source_file = b.path("metropolis.zig"),
            .target = target_options,
            .optimize = optimization_options,
            .use_llvm = use_llvm,
        });
        b.installArtifact(unit_tests);
    }
}
