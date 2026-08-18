const std = @import("std");

pub fn build(b: *std.Build) void {
    const main_module = b.createModule(.{
        .root_source_file = b.path("main.zig"),
        .target = b.graph.host,
    });

    const exe = b.addExecutable(.{
        .name = "main",
        .root_module = main_module,
    });

    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_exe.step);

    const unit_tests = b.addTest(.{
        .root_module = main_module,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Make the default `zig build` run tests after building the executable.
    b.getInstallStep().dependOn(&run_unit_tests.step);
}

