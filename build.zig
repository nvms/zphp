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
        .use_llvm = true,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.linkSystemLibrary("pcre2-8", .{ .preferred_link_mode = .static });
    exe_mod.linkSystemLibrary("sqlite3", .{ .preferred_link_mode = .static });
    exe_mod.linkSystemLibrary("z", .{ .preferred_link_mode = .static });
    exe_mod.linkSystemLibrary("mysqlclient", .{});
    exe_mod.linkSystemLibrary("pq", .{});
    exe_mod.linkSystemLibrary("ssl", .{ .preferred_link_mode = .static, .use_pkg_config = .no });
    exe_mod.linkSystemLibrary("crypto", .{ .preferred_link_mode = .static, .use_pkg_config = .no });
    exe_mod.linkSystemLibrary("nghttp2", .{ .preferred_link_mode = .static });
    exe_mod.linkSystemLibrary("curl", .{});
    addLibxml2(b, exe_mod);
    exe_mod.link_libc = true;
    exe_mod.addObject(fast_loop_obj);

    const exe = b.addExecutable(.{
        .name = "zphp",
        .root_module = exe_mod,
        .use_llvm = true,
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
        .use_llvm = true,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    test_mod.linkSystemLibrary("pcre2-8", .{ .preferred_link_mode = .static });
    test_mod.linkSystemLibrary("sqlite3", .{ .preferred_link_mode = .static });
    test_mod.linkSystemLibrary("z", .{ .preferred_link_mode = .static });
    test_mod.linkSystemLibrary("mysqlclient", .{});
    test_mod.linkSystemLibrary("pq", .{});
    test_mod.linkSystemLibrary("ssl", .{ .preferred_link_mode = .static, .use_pkg_config = .no });
    test_mod.linkSystemLibrary("crypto", .{ .preferred_link_mode = .static, .use_pkg_config = .no });
    test_mod.linkSystemLibrary("nghttp2", .{ .preferred_link_mode = .static });
    test_mod.linkSystemLibrary("curl", .{});
    addLibxml2(b, test_mod);
    test_mod.link_libc = true;
    test_mod.addObject(fast_loop_test_obj);

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
        .use_llvm = true,
    });
    unit_tests.stack_size = 64 * 1024 * 1024;

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

// libxml2 ships its headers under a libxml2/ subdirectory. pkg-config name is
// libxml-2.0 (not "xml2"), and on macos pkg-config returns the parent include
// dir without the libxml2/ suffix that the headers actually live in. resolve
// the includedir via pkg-config / xml2-config and append libxml2/ explicitly
fn addLibxml2(b: *std.Build, mod: *std.Build.Module) void {
    mod.linkSystemLibrary("xml2", .{ .use_pkg_config = .no });

    if (pkgConfigVariable(b, "libxml-2.0", "includedir")) |inc| {
        const sub = std.fs.path.join(b.allocator, &.{ inc, "libxml2" }) catch return;
        mod.addSystemIncludePath(.{ .cwd_relative = sub });
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
        return;
    }
    if (xml2ConfigIncludeDir(b)) |inc| {
        const sub = std.fs.path.join(b.allocator, &.{ inc, "libxml2" }) catch return;
        mod.addSystemIncludePath(.{ .cwd_relative = sub });
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
    }
}

fn pkgConfigVariable(b: *std.Build, pkg: []const u8, name: []const u8) ?[]const u8 {
    const arg = std.fmt.allocPrint(b.allocator, "--variable={s}", .{name}) catch return null;
    const r = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "pkg-config", arg, pkg },
    }) catch return null;
    if (r.term != .Exited or r.term.Exited != 0) return null;
    return std.mem.trim(u8, r.stdout, " \t\r\n");
}

fn xml2ConfigIncludeDir(b: *std.Build) ?[]const u8 {
    const r = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "xml2-config", "--cflags" },
    }) catch return null;
    if (r.term != .Exited or r.term.Exited != 0) return null;
    var it = std.mem.tokenizeAny(u8, r.stdout, " \t\r\n");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-I")) return tok[2..];
    }
    return null;
}
