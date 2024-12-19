const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});
    const mini_python = b.addModule("mini_python", .{
        .root_source_file = b.path("src/mini_python.zig"),
    });

    const exe = b.addExecutable(.{
        .name = "main",
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
    });

    exe.root_module.addImport("mini-python", mini_python);
    b.installArtifact(exe);

    const unit_tests_step = step: {
        var unit_tests = b.addTest(.{
            .root_source_file = b.path("src/mini_python.zig"),
        });
        for (mini_python.import_table.keys(), mini_python.import_table.values()) |name, import| {
            unit_tests.root_module.addImport(name, import);
        }

        const run_test = b.addRunArtifact(unit_tests);

        const unit_tests_step = b.step("unit tests", "Run the unit tests");
        unit_tests_step.dependOn(&run_test.step);
        break :step unit_tests_step;
    };

    const tests_step = b.step("test", "Run all tests");
    tests_step.dependOn(unit_tests_step);
}
