const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target_options = b.standardTargetOptions(.{});
    const optimization_options = b.standardOptimizeOption(.{});

    const use_llvm = if (optimization_options == std.builtin.OptimizeMode.Debug) false else true;

    const root_module = b.createModule(.{
        .root_source_file = b.path("metropolis.zig"),
        .target = target_options,
        .optimize = optimization_options,
        .strip = b.option(bool, "strip", "Strip debugging symbols (or not)"),
        .omit_frame_pointer = b.option(bool, "omit-frame-pointer", "Omit the frame pointer (or not)"),
    });

    const exe = b.addExecutable(.{
        .name = "metropolis",
        .root_module = root_module,
        .use_llvm = use_llvm,
    });
    b.installArtifact(exe);

    if (b.option(bool, "build-tests", "Build the test suite") orelse false) {
        const unit_tests = b.addTest(.{
            .name = "test",
            .root_module = root_module,
            .use_llvm = use_llvm,
        });
        b.installArtifact(unit_tests);
        b.installDirectory(.{
            .source_dir = b.path("src/test_data"),
            .install_dir = .bin,
            .install_subdir = "test_data",
        });
    }
}
