const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const datetime = b.dependency("datetime", .{
        .target = target,
        .optimize = optimize,
    });

    const hissylogz_lib = b.addStaticLibrary(.{
        .name = "hissylogz",
        .root_source_file = b.path("src/hissylogz.zig"),
        .target = target,
        .optimize = optimize,
    });
    hissylogz_lib.root_module.addImport("datetime", datetime.module("datetime"));

    b.installArtifact(hissylogz_lib);

    _ = b.addModule("hissylogz", .{
        .root_source_file = b.path("src/hissylogz.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "datetime", .module = datetime.module("datetime") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "hissylogz-demo",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("datetime", datetime.module("datetime"));
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const hissylogz_lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/hissylogz.zig"),
        .target = target,
        .optimize = optimize,
    });
    hissylogz_lib_unit_tests.root_module.addImport("datetime", datetime.module("datetime"));

    const run_hissylogz_lib_unit_tests = b.addRunArtifact(hissylogz_lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("datetime", datetime.module("datetime"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_hissylogz_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}

// ---
// hissylogz.
//
// Copyright 2024 Kevin Poalses.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the “Software”), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
