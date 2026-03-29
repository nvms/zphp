const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // fastLoop compiled as a separate object so LLVM optimizes it
    // independently of runLoop (prevents codegen perturbation)
    const fast_loop_mod = b.createModule(.{
        .root_source_file = b.path("src/fast_loop.zig"),
        .target = target,
        .optimize = optimize,
    });
    fast_loop_mod.link_libc = true;

    const fast_loop_obj = b.addObject(.{
        .name = "fast_loop",
        .root_module = fast_loop_mod,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.linkSystemLibrary("pcre2-8", .{});
    exe_mod.linkSystemLibrary("sqlite3", .{});
    exe_mod.linkSystemLibrary("z", .{});
    exe_mod.linkSystemLibrary("mysqlclient", .{});
    exe_mod.linkSystemLibrary("pq", .{});
    exe_mod.linkSystemLibrary("ssl", .{ .use_pkg_config = .no });
    exe_mod.linkSystemLibrary("crypto", .{ .use_pkg_config = .no });
    exe_mod.linkSystemLibrary("nghttp2", .{});
    exe_mod.link_libc = true;
    exe_mod.addObject(fast_loop_obj);

    const exe = b.addExecutable(.{
        .name = "zphp",
        .root_module = exe_mod,
    });
    exe.stack_size = 64 * 1024 * 1024;
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run zphp");
    run_step.dependOn(&run_cmd.step);

    const fast_loop_test_obj = b.addObject(.{
        .name = "fast_loop_test",
        .root_module = fast_loop_mod,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    test_mod.linkSystemLibrary("pcre2-8", .{});
    test_mod.linkSystemLibrary("sqlite3", .{});
    test_mod.linkSystemLibrary("z", .{});
    test_mod.linkSystemLibrary("mysqlclient", .{});
    test_mod.linkSystemLibrary("pq", .{});
    test_mod.linkSystemLibrary("ssl", .{ .use_pkg_config = .no });
    test_mod.linkSystemLibrary("crypto", .{ .use_pkg_config = .no });
    test_mod.linkSystemLibrary("nghttp2", .{});
    test_mod.link_libc = true;
    test_mod.addObject(fast_loop_test_obj);

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
    });
    unit_tests.stack_size = 64 * 1024 * 1024;

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
