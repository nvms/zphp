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

    // static extensions: C sources compiled into the binary. the generated
    // module lists their entry points so the loader finds them without dlopen
    const extension_sources = b.option([]const []const u8, "extension", "C source of a static extension, repeatable; the file stem is the extension name") orelse &.{};
    const static_extensions = staticExtensionsModule(b, extension_sources);
    exe_mod.addImport("static_extensions", static_extensions);
    fast_loop_mod.addImport("static_extensions", static_extensions);
    for (extension_sources) |source| {
        exe_mod.addCSourceFile(.{ .file = .{ .cwd_relative = source }, .flags = &.{ "-std=c11", "-DZPHP_STATIC_EXTENSION" } });
    }
    exe_mod.addIncludePath(b.path("include"));

    exe_mod.linkSystemLibrary("pcre2-8", .{ .preferred_link_mode = .static });
    exe_mod.linkSystemLibrary("sqlite3", .{ .preferred_link_mode = .static });
    exe_mod.linkSystemLibrary("z", .{ .preferred_link_mode = .static });
    addMysqlClient(b, exe_mod);
    exe_mod.linkSystemLibrary("pq", .{});
    addOpenSsl(b, exe_mod);
    exe_mod.linkSystemLibrary("nghttp2", .{ .preferred_link_mode = .static });
    exe_mod.linkSystemLibrary("curl", .{});
    addLibxml2(b, exe_mod);
    addLibicu(b, exe_mod);
    addIcuShim(b, exe_mod);
    addLibgmp(b, exe_mod);
    addLibgd(b, exe_mod);
    addLibsodium(b, exe_mod);
    addLibldap(b, exe_mod);
    addXxhashShim(b, exe_mod);
    addFsSpaceShim(b, exe_mod);
    exe_mod.link_libc = true;
    exe_mod.addObject(fast_loop_obj);

    // musl release binaries are fully static so they run on any linux. every
    // system library becomes the path of its archive, the archives behind
    // them come from pkg-config's static view, and the exe is linked -static
    const static_musl = target.result.abi.isMusl();
    if (static_musl) {
        addStaticDependencies(b, exe_mod);
        addGccLibstdcxx(b, exe_mod);
        pinStaticArchives(b, exe_mod);
    }

    // -Dframe-pointers keeps frame pointers in release builds so `sample`
    // and perf can unwind the stack when profiling by time
    if (b.option(bool, "frame-pointers", "keep frame pointers for profiling") orelse false) {
        exe_mod.omit_frame_pointer = false;
        fast_loop_mod.omit_frame_pointer = false;
    }

    const exe = b.addExecutable(.{
        .name = "zphp",
        .root_module = exe_mod,
        .use_llvm = true,
        .linkage = if (static_musl) .static else null,
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
    test_mod.addImport("static_extensions", static_extensions);

    test_mod.linkSystemLibrary("pcre2-8", .{ .preferred_link_mode = .static });
    test_mod.linkSystemLibrary("sqlite3", .{ .preferred_link_mode = .static });
    test_mod.linkSystemLibrary("z", .{ .preferred_link_mode = .static });
    addMysqlClient(b, test_mod);
    test_mod.linkSystemLibrary("pq", .{});
    addOpenSsl(b, test_mod);
    test_mod.linkSystemLibrary("nghttp2", .{ .preferred_link_mode = .static });
    test_mod.linkSystemLibrary("curl", .{});
    addLibxml2(b, test_mod);
    addLibicu(b, test_mod);
    addIcuShim(b, test_mod);
    addLibgmp(b, test_mod);
    addLibgd(b, test_mod);
    addLibsodium(b, test_mod);
    addLibldap(b, test_mod);
    addXxhashShim(b, test_mod);
    addFsSpaceShim(b, test_mod);
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

fn addOpenSsl(b: *std.Build, mod: *std.Build.Module) void {
    mod.linkSystemLibrary("ssl", .{ .preferred_link_mode = .static, .use_pkg_config = .no });
    mod.linkSystemLibrary("crypto", .{ .preferred_link_mode = .static, .use_pkg_config = .no });
    if (pkgConfigVariable(b, "openssl", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }
}

// ubuntu and homebrew ship mysqlclient.pc. alpine ships the same API as
// libmariadb.pc (mariadb-connector-c-dev) with headers under /usr/include/mysql
// and the static archive in mariadb-static
fn addMysqlClient(b: *std.Build, mod: *std.Build.Module) void {
    if (pkgConfigVariable(b, "mysqlclient", "libdir") != null) {
        mod.linkSystemLibrary("mysqlclient", .{});
        return;
    }
    if (pkgConfigVariable(b, "libmariadb", "includedir")) |inc| {
        mod.addIncludePath(.{ .cwd_relative = inc });
        mod.linkSystemLibrary("mariadb", .{ .preferred_link_mode = .static });
        return;
    }
    mod.linkSystemLibrary("mysqlclient", .{});
}

// every -l and -L that `pkg-config --static --libs` reports for the libraries
// zphp links, so a static musl link sees the archives behind each archive
// (curl needs nghttp2, brotli, zstd, idn2, psl; gd needs png, jpeg, webp,
// freetype; ldap needs sasl; ...). packages without a .pc file are covered
// by the direct linkSystemLibrary calls above
fn addStaticDependencies(b: *std.Build, mod: *std.Build.Module) void {
    const pkgs = [_][]const u8{ "libpcre2-8", "sqlite3", "zlib", "libmariadb", "libpq", "openssl", "libnghttp2", "libcurl", "libxml-2.0", "icu-i18n", "icu-uc", "gmp", "gdlib", "libsodium", "ldap", "lber" };
    const target = mod.resolved_target.?.result;
    for (pkgs) |pkg| {
        const r = std.process.Child.run(.{
            .allocator = b.allocator,
            .argv = &.{ "pkg-config", "--static", "--libs", pkg },
        }) catch continue;
        if (r.term != .Exited or r.term.Exited != 0) continue;
        var it = std.mem.tokenizeAny(u8, r.stdout, " \t\r\n");
        while (it.next()) |flag| {
            if (std.mem.startsWith(u8, flag, "-l")) {
                const name = staticArchiveName(flag[2..]);
                if (std.zig.target.isLibCLibName(&target, name)) continue;
                mod.linkSystemLibrary(name, .{ .use_pkg_config = .no });
            } else if (std.mem.startsWith(u8, flag, "-L")) {
                mod.addLibraryPath(.{ .cwd_relative = flag[2..] });
            }
        }
    }
}

// libpq.pc names libpgcommon and libpgport, but those archives are the
// frontend builds with the encoding symbols renamed to *_private; the copies
// libpq.a itself was linked against are the _shlib archives
fn staticArchiveName(name: []const u8) []const u8 {
    if (std.mem.eql(u8, name, "pgcommon")) return "pgcommon_shlib";
    if (std.mem.eql(u8, name, "pgport")) return "pgport_shlib";
    return name;
}

// alpine's icu archives are gcc builds that pull in libstdc++ internals, so
// gcc's libstdc++.a is linked alongside the libc++ zig links for the icu shim.
// zig treats -lstdc++ as a request for its own libc++, hence the archive path
fn addGccLibstdcxx(b: *std.Build, mod: *std.Build.Module) void {
    const r = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "cc", "-print-file-name=libstdc++.a" },
    }) catch return;
    if (r.term != .Exited or r.term.Exited != 0) return;
    const path = std.mem.trim(u8, r.stdout, " \r\n");
    if (!std.fs.path.isAbsolute(path)) return;
    mod.addObjectFile(.{ .cwd_relative = path });
}

// zig resolves -l flags with the mode in force when it parses them, and the
// build system emits -static after them, so a -l would still pick a shared
// object. archive paths sidestep that: they are plain link inputs
fn pinStaticArchives(b: *std.Build, mod: *std.Build.Module) void {
    for (mod.link_objects.items) |*obj| switch (obj.*) {
        .system_lib => |lib| obj.* = .{ .static_path = .{ .cwd_relative = findStaticArchive(b, mod, lib.name) } },
        else => {},
    };
}

fn findStaticArchive(b: *std.Build, mod: *std.Build.Module, name: []const u8) []const u8 {
    const file = b.fmt("lib{s}.a", .{name});
    for (mod.lib_paths.items) |lib_path| {
        const dir = switch (lib_path) {
            .cwd_relative => |p| p,
            else => continue,
        };
        if (archiveIn(b, dir, file)) |path| return path;
    }
    for ([_][]const u8{ "/usr/local/lib", "/usr/lib" }) |dir| {
        if (archiveIn(b, dir, file)) |path| return path;
    }
    std.debug.panic("no static archive lib{s}.a for the musl build", .{name});
}

fn archiveIn(b: *std.Build, dir: []const u8, file: []const u8) ?[]const u8 {
    const path = b.pathJoin(&.{ dir, file });
    std.fs.cwd().access(path, .{}) catch return null;
    return path;
}

fn staticExtensionsModule(b: *std.Build, sources: []const []const u8) *std.Build.Module {
    var code = std.ArrayListUnmanaged(u8){};
    const w = code.writer(b.allocator);
    w.writeAll("pub const Entry = *const fn (*const anyopaque) callconv(.c) ?*const anyopaque;\n") catch @panic("OOM");
    w.writeAll("pub const StaticExtension = struct { name: []const u8, entry: Entry };\n") catch @panic("OOM");
    for (sources) |source| {
        const stem = std.fs.path.stem(source);
        if (!validIdentifier(stem)) std.debug.panic("-Dextension={s}: the file stem must be a C identifier, it names the extension entry", .{source});
        w.print("extern fn zphp_extension_entry_{s}(api: *const anyopaque) callconv(.c) ?*const anyopaque;\n", .{stem}) catch @panic("OOM");
    }
    w.writeAll("pub const entries = [_]StaticExtension{") catch @panic("OOM");
    for (sources) |source| {
        const stem = std.fs.path.stem(source);
        w.print(" .{{ .name = \"{s}\", .entry = &zphp_extension_entry_{s} }},", .{ source, stem }) catch @panic("OOM");
    }
    w.writeAll(" };\n") catch @panic("OOM");
    const files = b.addWriteFiles();
    const path = files.add("static_extensions.zig", code.items);
    return b.createModule(.{ .root_source_file = path });
}

fn validIdentifier(s: []const u8) bool {
    if (s.len == 0 or std.ascii.isDigit(s[0])) return false;
    for (s) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) return false;
    return true;
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

// libicu is split across three libraries (icuuc, icui18n, icudata) with pkg-config
// names icu-uc, icu-i18n. on macos it's keg-only (brew install icu4c) so its
// pkg-config dir must be on PKG_CONFIG_PATH. on alpine, icu-dev / icu-static
fn addLibicu(b: *std.Build, mod: *std.Build.Module) void {
    mod.linkSystemLibrary("icui18n", .{ .use_pkg_config = .no });
    mod.linkSystemLibrary("icuuc", .{ .use_pkg_config = .no });
    mod.linkSystemLibrary("icudata", .{ .use_pkg_config = .no });
    if (pkgConfigVariable(b, "icu-i18n", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }
}

// icu_shim.c wraps every ICU function we use behind a zphp_* name. compiling
// it through the C preprocessor lets libicu's rename macros (u_strFromUTF8 ->
// u_strFromUTF8_77) be applied so the resulting object file links to the right
// versioned symbols. zig's @cImport doesn't apply these renames, which is why
// intl.zig declares the zphp_* symbols as plain externs instead of @cImport-ing
// libicu headers
// vendored xxhash (single-header); compiled inline so xxh128 doesn't add a
// system library dependency on every CI runner
fn addFsSpaceShim(b: *std.Build, mod: *std.Build.Module) void {
    mod.addCSourceFile(.{
        .file = b.path("src/stdlib/fs_space_shim.c"),
        .flags = &.{"-std=c11"},
    });
}

fn addXxhashShim(b: *std.Build, mod: *std.Build.Module) void {
    mod.addCSourceFile(.{
        .file = b.path("src/stdlib/xxhash_shim.c"),
        .flags = &.{"-std=c11"},
    });
}

fn addIcuShim(b: *std.Build, mod: *std.Build.Module) void {
    var flags = std.ArrayList([]const u8){};
    defer flags.deinit(b.allocator);
    flags.append(b.allocator, "-std=c11") catch {};
    if (pkgConfigCflagsIncludes(b, "icu-i18n")) |inc| {
        const flag = std.fmt.allocPrint(b.allocator, "-I{s}", .{inc}) catch return;
        flags.append(b.allocator, flag) catch {};
    }
    mod.addCSourceFile(.{
        .file = b.path("src/stdlib/icu_shim.c"),
        .flags = flags.items,
    });

    // MessageFormat shim is C++ since ICU's named-arg MessageFormat is only
    // exposed in the C++ API. link libc++ once for the whole module
    var cpp_flags = std.ArrayList([]const u8){};
    defer cpp_flags.deinit(b.allocator);
    cpp_flags.append(b.allocator, "-std=c++17") catch {};
    if (pkgConfigCflagsIncludes(b, "icu-i18n")) |inc| {
        const flag = std.fmt.allocPrint(b.allocator, "-I{s}", .{inc}) catch return;
        cpp_flags.append(b.allocator, flag) catch {};
    }
    mod.addCSourceFile(.{
        .file = b.path("src/stdlib/icu_msg_shim.cpp"),
        .flags = cpp_flags.items,
    });
    mod.link_libcpp = true;
}

// libgmp ships a clean pkg-config and uses static `mpz_*` -> `__gmpz_*` macros
// (no per-version renaming). zig's translate-c handles simple macro renames
fn addLibgmp(b: *std.Build, mod: *std.Build.Module) void {
    mod.linkSystemLibrary("gmp", .{ .use_pkg_config = .no });
    if (pkgConfigCflagsIncludes(b, "gmp")) |inc| {
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
    }
    if (pkgConfigVariable(b, "gmp", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }

    // shim file: compiled by C compiler so the `mpz_*` -> `__gmpz_*` macros
    // resolve correctly. zig then links against the unversioned zphp_mpz_*
    var flags = std.ArrayList([]const u8){};
    defer flags.deinit(b.allocator);
    flags.append(b.allocator, "-std=c11") catch return;
    if (pkgConfigCflagsIncludes(b, "gmp")) |inc| {
        const f = std.fmt.allocPrint(b.allocator, "-I{s}", .{inc}) catch return;
        flags.append(b.allocator, f) catch return;
    }
    mod.addCSourceFile(.{
        .file = b.path("src/stdlib/gmp_shim.c"),
        .flags = flags.items,
    });
}

// libgd uses simple unversioned symbols. pkg-config name is "gdlib"
fn addLibgd(b: *std.Build, mod: *std.Build.Module) void {
    mod.linkSystemLibrary("gd", .{ .use_pkg_config = .no });
    if (pkgConfigCflagsIncludes(b, "gdlib")) |inc| {
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
    }
    if (pkgConfigVariable(b, "gdlib", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }
}

fn addLibsodium(b: *std.Build, mod: *std.Build.Module) void {
    mod.linkSystemLibrary("sodium", .{ .use_pkg_config = .no });
    if (pkgConfigCflagsIncludes(b, "libsodium")) |inc| {
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
    }
    if (pkgConfigVariable(b, "libsodium", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }
}

fn addLibldap(b: *std.Build, mod: *std.Build.Module) void {
    mod.linkSystemLibrary("ldap", .{ .use_pkg_config = .no });
    mod.linkSystemLibrary("lber", .{ .use_pkg_config = .no });
    if (pkgConfigCflagsIncludes(b, "ldap")) |inc| {
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
    }
    if (pkgConfigVariable(b, "ldap", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }
}

fn pkgConfigCflagsIncludes(b: *std.Build, pkg: []const u8) ?[]const u8 {
    const r = std.process.Child.run(.{
        .allocator = b.allocator,
        .argv = &.{ "pkg-config", "--cflags-only-I", pkg },
    }) catch return null;
    if (r.term != .Exited or r.term.Exited != 0) return null;
    var it = std.mem.tokenizeAny(u8, r.stdout, " \t\r\n");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-I")) return tok[2..];
    }
    return null;
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
