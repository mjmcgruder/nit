const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target_options = b.standardTargetOptions(.{});
    const optimization_options = b.standardOptimizeOption(.{});

    // options

    const profile: ?bool = b.option(
        bool,
        "profile",
        "keep debug symbols + frame pointer",
    );
    var not_profile: ?bool = null;
    if (profile) |val| {
        not_profile = !val;
    }

    const use_llvm: ?bool = b.option(
        bool,
        "use-llvm",
        "force use of llvm",
    );

    const build_tests: bool = b.option(
        bool,
        "build-tests",
        "Build the test suite",
    ) orelse false;

    const root_module = b.createModule(.{
        .root_source_file = b.path("metropolis.zig"),
        .target = target_options,
        .optimize = optimization_options,
        .strip = not_profile,
        .omit_frame_pointer = not_profile,
    });

    // main executable

    const exe = b.addExecutable(.{
        .name = "metropolis",
        .root_module = root_module,
        .use_llvm = use_llvm,
    });
    b.installArtifact(exe);

    // test suite

    if (build_tests) {
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
