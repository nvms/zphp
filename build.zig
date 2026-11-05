const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // the fast loop object compiles the runtime too; this tells that copy to
    // reach shared per-thread state through the main object's exports
    const fast_loop_role = b.addOptions();
    fast_loop_role.addOption(bool, "fast_loop_object", true);
    const build_epoch = buildEpoch(b);
    fast_loop_role.addOption(i64, "build_epoch", build_epoch);
    const main_role = b.addOptions();
    main_role.addOption(bool, "fast_loop_object", false);
    main_role.addOption([]const u8, "compiler_hash", compilerHash(b));
    main_role.addOption(i64, "build_epoch", build_epoch);

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
    exe_mod.addOptions("build_role", main_role);
    for (extension_sources) |source| {
        exe_mod.addCSourceFile(.{ .file = .{ .cwd_relative = source }, .flags = &.{ "-std=c11", "-DZPHP_STATIC_EXTENSION" } });
    }
    exe_mod.addIncludePath(b.path("include"));

    const fast_loop_mod = fastLoopModule(b, target, optimize, fast_loop_role, static_extensions);
    const fast_loop_obj = b.addObject(.{
        .name = "fast_loop",
        .root_module = fast_loop_mod,
        .use_llvm = true,
    });

    linkLib(b, exe_mod, "libpcre2-8", "pcre2-8", .static, .yes);
    linkLib(b, exe_mod, "sqlite3", "sqlite3", .static, .yes);
    linkLib(b, exe_mod, "zlib", "z", .static, .yes);
    addMysqlClient(b, exe_mod);
    addLibpq(b, exe_mod);
    addOpenSsl(b, exe_mod);
    linkLib(b, exe_mod, "libnghttp2", "nghttp2", .static, .yes);
    linkLib(b, exe_mod, "libcurl", "curl", .dynamic, .yes);
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

    // the C headers the runtime binds, translated with the include paths the
    // executable's libraries resolved to. every module compiling the runtime
    // imports the same translations, so their types agree
    const c_imports = cImportModules(b, target, optimize, exe_mod);
    addCImports(exe_mod, c_imports);
    addCImports(fast_loop_mod, c_imports);

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
    run_cmd.addPassthruArgs();

    const fast_loop_object_step = b.step("fast-loop-object", "Install the fast loop object for inspection");
    fast_loop_object_step.dependOn(&b.addInstallFile(fast_loop_obj.getEmittedBin(), "fast_loop.o").step);

    const run_step = b.step("run", "Run zphp");
    run_step.dependOn(&run_cmd.step);

    // a module belongs to one compilation, so the test build's fast loop
    // object gets its own copy of the fast loop module
    const fast_loop_test_mod = fastLoopModule(b, target, optimize, fast_loop_role, static_extensions);
    addCImports(fast_loop_test_mod, c_imports);
    const fast_loop_test_obj = b.addObject(.{
        .name = "fast_loop_test",
        .root_module = fast_loop_test_mod,
        .use_llvm = true,
    });

    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        // a failing test prints its stack trace
        .strip = false,
    });
    test_mod.addImport("static_extensions", static_extensions);
    test_mod.addOptions("build_role", main_role);

    linkLib(b, test_mod, "libpcre2-8", "pcre2-8", .static, .yes);
    linkLib(b, test_mod, "sqlite3", "sqlite3", .static, .yes);
    linkLib(b, test_mod, "zlib", "z", .static, .yes);
    addMysqlClient(b, test_mod);
    addLibpq(b, test_mod);
    addOpenSsl(b, test_mod);
    linkLib(b, test_mod, "libnghttp2", "nghttp2", .static, .yes);
    linkLib(b, test_mod, "libcurl", "curl", .dynamic, .yes);
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
    addCImports(test_mod, c_imports);

    const unit_tests = b.addTest(.{
        .root_module = test_mod,
        .use_llvm = true,
    });
    unit_tests.stack_size = 64 * 1024 * 1024;

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}

// fastLoop compiled as a separate object so LLVM optimizes it
// independently of runLoop (prevents codegen perturbation)
fn fastLoopModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, role: *std.Build.Step.Options, static_extensions: *std.Build.Module) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/fast_loop.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod.addOptions("build_role", role);
    mod.addImport("static_extensions", static_extensions);
    return mod;
}

const CImport = struct {
    // module name, also src/c/<name without the c_ prefix>.h
    name: []const u8,
    // pkg-config packages whose cflags the header needs
    pkgs: []const []const u8,
};

const c_import_specs = [_]CImport{
    .{ .name = "c_zlib", .pkgs = &.{"zlib"} },
    .{ .name = "c_stdlib", .pkgs = &.{} },
    .{ .name = "c_curl", .pkgs = &.{"libcurl"} },
    .{ .name = "c_nghttp2", .pkgs = &.{"libnghttp2"} },
    .{ .name = "c_soap", .pkgs = &.{ "libcurl", "libxml-2.0" } },
    .{ .name = "c_gd", .pkgs = &.{"gdlib"} },
    .{ .name = "c_ldap", .pkgs = &.{"ldap"} },
    .{ .name = "c_libxml_tree", .pkgs = &.{"libxml-2.0"} },
    .{ .name = "c_mysql", .pkgs = &.{ "mysqlclient", "libmariadb" } },
    .{ .name = "c_openssl", .pkgs = &.{"openssl"} },
    .{ .name = "c_tls", .pkgs = &.{"openssl"} },
    .{ .name = "c_sodium", .pkgs = &.{"libsodium"} },
    .{ .name = "c_xmlreader", .pkgs = &.{"libxml-2.0"} },
    .{ .name = "c_xmlwriter", .pkgs = &.{"libxml-2.0"} },
};

const CImports = [c_import_specs.len]*std.Build.Module;

fn cImportModules(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, from: *std.Build.Module) CImports {
    var mods: CImports = undefined;
    for (c_import_specs, 0..) |spec, i| {
        const tc = b.addTranslateC(.{
            .root_source_file = b.path(b.fmt("src/c/{s}.h", .{spec.name[2..]})),
            .target = target,
            .optimize = optimize,
        });
        for (from.include_dirs.items) |dir| switch (dir) {
            // every directory as a system path, so one that pkg-config also
            // reports doesn't arrive both ways
            .path, .path_system => |path| tc.addSystemIncludePath(path),
            .path_after => |path| tc.addAfterIncludePath(path),
            .framework_path => |path| tc.addFrameworkPath(path),
            .framework_path_system => |path| tc.addSystemFrameworkPath(path),
            .other_step, .config_header_step, .embed_path => {},
        };
        for (spec.pkgs) |pkg| {
            const out = capture(b, &.{ "pkg-config", "--cflags", pkg }) orelse continue;
            var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
            while (it.next()) |flag| {
                // as system paths, like the ones the modules carry, so a
                // directory named both ways doesn't conflict
                if (std.mem.startsWith(u8, flag, "-I")) {
                    tc.addSystemIncludePath(.{ .cwd_relative = b.dupe(flag[2..]) });
                } else {
                    tc.addCFlags(&.{b.dupe(flag)});
                }
            }
        }
        mods[i] = tc.createModule();
    }
    return mods;
}

fn addCImports(mod: *std.Build.Module, mods: CImports) void {
    for (c_import_specs, mods) |spec, m| mod.addImport(spec.name, m);
}

// libxml2 ships its headers under a libxml2/ subdirectory. pkg-config name is
// libxml-2.0 (not "xml2"), and on macos pkg-config returns the parent include
// dir without the libxml2/ suffix that the headers actually live in. resolve
// the includedir via pkg-config / xml2-config and append libxml2/ explicitly
fn addLibxml2(b: *std.Build, mod: *std.Build.Module) void {
    linkLib(b, mod, "libxml-2.0", "xml2", .dynamic, .no);

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
    linkLib(b, mod, "libssl", "ssl", .static, .no);
    linkLib(b, mod, "libcrypto", "crypto", .static, .no);
    if (mod.resolved_target.?.result.os.tag != .windows) linkCryptoDependencies(b, mod);
    if (pkgConfigVariable(b, "openssl", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }
}

// a static libcrypto needs whatever openssl was built against: ubuntu 26.04's
// openssl 3.5 pulls in zstd and jitterentropy (spelled -l:libjitterentropy.a),
// older builds only zlib and dl
fn linkCryptoDependencies(b: *std.Build, mod: *std.Build.Module) void {
    const target = mod.resolved_target.?.result;
    const out = capture(b, &.{ "pkg-config", "--static", "--libs-only-l", "libcrypto" }) orelse return;
    var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
    while (it.next()) |flag| {
        const name = libFlagName(flag) orelse continue;
        if (std.mem.eql(u8, name, "crypto") or std.zig.target.isLibCLibName(&target, name)) continue;
        mod.linkSystemLibrary(name, .{ .preferred_link_mode = .static, .use_pkg_config = .no });
    }
}

// the library a -l flag names: -lfoo and -l:libfoo.a both give foo
fn libFlagName(flag: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, flag, "-l")) return null;
    const name = flag[2..];
    if (!std.mem.startsWith(u8, name, ":")) return name;
    const file = name[1..];
    if (!std.mem.startsWith(u8, file, "lib")) return null;
    if (std.mem.endsWith(u8, file, ".a")) return file[3 .. file.len - 2];
    if (std.mem.endsWith(u8, file, ".so")) return file[3 .. file.len - 3];
    return null;
}

// ubuntu and homebrew ship mysqlclient.pc. alpine ships the same API as
// libmariadb.pc (mariadb-connector-c-dev) with headers under /usr/include/mysql
// and the static archive in mariadb-static
fn addMysqlClient(b: *std.Build, mod: *std.Build.Module) void {
    // mingw's static mysql and postgres archives bundle their own ed25519 and
    // pthread shims that collide with libsodium and winpthreads, so on windows
    // those two come in through their import libraries and load as dlls
    if (mod.resolved_target.?.result.os.tag == .windows) {
        const pkg: []const u8 = if (pkgConfigVariable(b, "mysqlclient", "libdir") != null) "mysqlclient" else "libmariadb";
        if (pkgConfigVariable(b, pkg, "includedir")) |inc| mod.addIncludePath(.{ .cwd_relative = inc });
        linkWindowsImport(b, mod, pkg, "mariadb");
        return;
    }
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
        const out = capture(b, &.{ "pkg-config", "--static", "--libs", pkg }) orelse continue;
        var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
        while (it.next()) |flag| {
            if (libFlagName(flag)) |lib| {
                const name = staticArchiveName(lib);
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
    const out = capture(b, &.{ "cc", "-print-file-name=libstdc++.a" }) orelse return;
    const path = std.mem.trim(u8, out, " \r\n");
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
    std.Io.Dir.cwd().access(b.graph.io, path, .{}) catch return null;
    return path;
}

fn staticExtensionsModule(b: *std.Build, sources: []const []const u8) *std.Build.Module {
    var code: std.Io.Writer.Allocating = .init(b.allocator);
    const w = &code.writer;
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
    const path = files.add("static_extensions.zig", code.written());
    return b.createModule(.{ .root_source_file = path });
}

fn validIdentifier(s: []const u8) bool {
    if (s.len == 0 or std.ascii.isDigit(s[0])) return false;
    for (s) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '_')) return false;
    return true;
}

fn addLibpq(b: *std.Build, mod: *std.Build.Module) void {
    if (mod.resolved_target.?.result.os.tag == .windows) {
        if (pkgConfigVariable(b, "libpq", "includedir")) |inc| mod.addIncludePath(.{ .cwd_relative = inc });
        linkWindowsImport(b, mod, "libpq", "pq");
        return;
    }
    mod.linkSystemLibrary("pq", .{});
}

// one system library: on windows every dependency comes in through its mingw
// import library and loads as a dll (the static archives there bundle
// conflicting copies of pthreads, ed25519, and each other's dependencies);
// elsewhere it is a normal system library with the given preference
fn linkLib(b: *std.Build, mod: *std.Build.Module, pkg: []const u8, name: []const u8, mode: std.builtin.LinkMode, use_pkg_config: std.Build.Module.SystemLib.UsePkgConfig) void {
    if (mod.resolved_target.?.result.os.tag == .windows) return linkWindowsImport(b, mod, pkg, name);
    mod.linkSystemLibrary(name, .{ .preferred_link_mode = mode, .use_pkg_config = use_pkg_config });
}

// zig does not search for mingw's lib<name>.dll.a import libraries, so the
// file is handed to the linker as an input. a package without a .pc file
// lives in the same lib directory as zlib
fn linkWindowsImport(b: *std.Build, mod: *std.Build.Module, pkg: []const u8, name: []const u8) void {
    const libdir = pkgConfigVariable(b, pkg, "libdir") orelse pkgConfigVariable(b, "zlib", "libdir") orelse std.debug.panic("pkg-config has no libdir for {s}", .{pkg});
    mod.addObjectFile(.{ .cwd_relative = b.fmt("{s}/lib{s}.dll.a", .{ libdir, name }) });
    // zig only asks pkg-config for cflags when it links the library itself
    if (pkgConfigCflagsIncludes(b, pkg)) |inc| mod.addSystemIncludePath(.{ .cwd_relative = inc });
    if (pkgConfigVariable(b, pkg, "includedir")) |inc| mod.addSystemIncludePath(.{ .cwd_relative = inc });
}

// stdout of a command that exited 0, null when it can't run or fails
fn capture(b: *std.Build, argv: []const []const u8) ?[]const u8 {
    const r = std.process.run(b.allocator, b.graph.io, .{ .argv = argv }) catch return null;
    if (r.term != .exited or r.term.exited != 0) return null;
    return r.stdout;
}

fn pkgConfigVariable(b: *std.Build, pkg: []const u8, name: []const u8) ?[]const u8 {
    const arg = std.fmt.allocPrint(b.allocator, "--variable={s}", .{name}) catch return null;
    const out = capture(b, &.{ "pkg-config", arg, pkg }) orelse return null;
    return std.mem.trim(u8, out, " \t\r\n");
}

// libicu is split across three libraries (icuuc, icui18n, icudata) with pkg-config
// names icu-uc, icu-i18n. on macos it's keg-only (brew install icu4c) so its
// pkg-config dir must be on PKG_CONFIG_PATH. on alpine, icu-dev / icu-static
fn addLibicu(b: *std.Build, mod: *std.Build.Module) void {
    // icu's windows builds spell the libraries icuin, icuuc, icudt
    const windows = mod.resolved_target.?.result.os.tag == .windows;
    linkLib(b, mod, "icu-i18n", if (windows) "icuin" else "icui18n", .dynamic, .no);
    linkLib(b, mod, "icu-uc", "icuuc", .dynamic, .no);
    linkLib(b, mod, "icu-uc", if (windows) "icudt" else "icudata", .dynamic, .no);
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
    var flags = std.ArrayList([]const u8).empty;
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
    var cpp_flags = std.ArrayList([]const u8).empty;
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
    linkLib(b, mod, "gmp", "gmp", .dynamic, .no);
    if (pkgConfigCflagsIncludes(b, "gmp")) |inc| {
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
    }
    if (pkgConfigVariable(b, "gmp", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }

    // shim file: compiled by C compiler so the `mpz_*` -> `__gmpz_*` macros
    // resolve correctly. zig then links against the unversioned zphp_mpz_*
    var flags = std.ArrayList([]const u8).empty;
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
    linkLib(b, mod, "gdlib", "gd", .dynamic, .no);
    if (pkgConfigCflagsIncludes(b, "gdlib")) |inc| {
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
    }
    if (pkgConfigVariable(b, "gdlib", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }
}

fn addLibsodium(b: *std.Build, mod: *std.Build.Module) void {
    linkLib(b, mod, "libsodium", "sodium", .dynamic, .no);
    if (pkgConfigCflagsIncludes(b, "libsodium")) |inc| {
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
    }
    if (pkgConfigVariable(b, "libsodium", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }
}

fn addLibldap(b: *std.Build, mod: *std.Build.Module) void {
    linkLib(b, mod, "ldap", "ldap", .dynamic, .no);
    linkLib(b, mod, "lber", "lber", .dynamic, .no);
    if (pkgConfigCflagsIncludes(b, "ldap")) |inc| {
        mod.addSystemIncludePath(.{ .cwd_relative = inc });
    }
    if (pkgConfigVariable(b, "ldap", "libdir")) |lib| {
        mod.addLibraryPath(.{ .cwd_relative = lib });
    }
}

fn pkgConfigCflagsIncludes(b: *std.Build, pkg: []const u8) ?[]const u8 {
    const out = capture(b, &.{ "pkg-config", "--cflags-only-I", pkg }) orelse return null;
    var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-I")) return tok[2..];
    }
    return null;
}

fn xml2ConfigIncludeDir(b: *std.Build) ?[]const u8 {
    const out = capture(b, &.{ "xml2-config", "--cflags" }) orelse return null;
    var it = std.mem.tokenizeAny(u8, out, " \t\r\n");
    while (it.next()) |tok| {
        if (std.mem.startsWith(u8, tok, "-I")) return tok[2..];
    }
    return null;
}

// the on-disk bytecode cache is keyed by this, so a build whose compiler
// emits different bytecode never reads another build's entries
// the time PHP_BUILD_DATE reports: SOURCE_DATE_EPOCH for reproducible
// builds, else the commit being built, so a rebuild of the same tree doesn't
// invalidate the cache. 0 when neither is known
fn buildEpoch(b: *std.Build) i64 {
    if (b.graph.environ_map.get("SOURCE_DATE_EPOCH")) |v| {
        return std.fmt.parseInt(i64, std.mem.trim(u8, v, " \n"), 10) catch 0;
    }
    const out = capture(b, &.{ "git", "-C", b.root.root_dir.path orelse ".", "log", "-1", "--format=%ct" }) orelse return 0;
    return std.fmt.parseInt(i64, std.mem.trim(u8, out, " \r\n"), 10) catch 0;
}

fn compilerHash(b: *std.Build) []const u8 {
    var hasher = std.hash.Wyhash.init(0);
    const io = b.graph.io;
    var dir = b.root.root_dir.handle.openDir(io, "src/pipeline", .{ .iterate = true }) catch @panic("src/pipeline");
    defer dir.close(io);
    var names: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch @panic("src/pipeline")) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zig")) names.append(b.allocator, b.dupe(entry.name)) catch @panic("OOM");
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn lessThan(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.lessThan(u8, x, y);
        }
    }.lessThan);
    for (names.items) |name| {
        const bytes = dir.readFileAlloc(io, name, b.allocator, .limited(1 << 24)) catch @panic("src/pipeline");
        hasher.update(name);
        hasher.update(bytes);
    }
    const format = b.root.root_dir.handle.readFileAlloc(io, "src/bytecode_format.zig", b.allocator, .limited(1 << 24)) catch @panic("src/bytecode_format.zig");
    hasher.update(format);
    return b.fmt("{x:0>16}", .{hasher.final()});
}
