const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target_options = b.standardTargetOptions(.{});
    const optimization_options = b.standardOptimizeOption(.{});
    const profile: bool = b.option(
        bool,
        "profile",
        "keep debug symbols + frame pointer",
    ) orelse false;

    const root_module = b.createModule(.{
        .root_source_file = b.path("metropolis.zig"),
        .target = target_options,
        .optimize = optimization_options,
        .strip = !profile,
        .omit_frame_pointer = !profile,
    });

    const exe = b.addExecutable(.{
        .name = "metropolis",
        .root_module = root_module,
    });
    b.installArtifact(exe);

    if (b.option(bool, "build-tests", "Build the test suite") orelse false) {
        const unit_tests = b.addTest(.{
            .name = "test",
            .root_module = root_module,
        });
        b.installArtifact(unit_tests);
        b.installDirectory(.{
            .source_dir = b.path("src/test_data"),
            .install_dir = .bin,
            .install_subdir = "test_data",
        });
    }
}
