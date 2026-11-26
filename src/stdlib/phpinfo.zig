// phpinfo() and phpcredits() as php's cli prints them, ported from
// ext/standard/info.c (php_print_info and the php_info_print_* helpers with
// phpinfo_as_text set), ext/standard/credits.c, and main/php_ini.c's
// display_ini_entries. the module sections carry each extension's MINFO
// table as php prints it, minus rows describing build options zphp lacks
const std = @import("std");
const vm_mod = @import("../runtime/vm.zig");
const NativeContext = vm_mod.NativeContext;
const RuntimeError = vm_mod.RuntimeError;
const Value = @import("../runtime/value.zig").Value;
const platform = @import("../platform.zig");
const php_version = @import("../php_version.zig");
const ini_config = @import("../ini_config.zig");
const types = @import("types.zig");
const generated = @import("extensions_generated.zig");

pub const INFO_GENERAL: i64 = 1 << 0;
pub const INFO_CREDITS: i64 = 1 << 1;
pub const INFO_CONFIGURATION: i64 = 1 << 2;
pub const INFO_MODULES: i64 = 1 << 3;
pub const INFO_ENVIRONMENT: i64 = 1 << 4;
pub const INFO_VARIABLES: i64 = 1 << 5;
pub const INFO_LICENSE: i64 = 1 << 6;
pub const INFO_ALL: i64 = 0xFFFFFFFF;

pub const CREDITS_GROUP: i64 = 1 << 0;
pub const CREDITS_GENERAL: i64 = 1 << 1;
pub const CREDITS_SAPI: i64 = 1 << 2;
pub const CREDITS_MODULES: i64 = 1 << 3;
pub const CREDITS_DOCS: i64 = 1 << 4;
pub const CREDITS_FULLPAGE: i64 = 1 << 5;
pub const CREDITS_QA: i64 = 1 << 6;
pub const CREDITS_WEB: i64 = 1 << 7;
pub const CREDITS_ALL: i64 = 0xFFFFFFFF;

const Out = struct {
    ctx: *NativeContext,
    // phpinfo() sorts the directives first (zend_ini_sort_entries); a
    // module printed alone lists them as registered
    sorted: bool = true,

    fn print(self: Out, s: []const u8) RuntimeError!void {
        try self.ctx.vm.output.appendSlice(self.ctx.allocator, s);
    }

    fn printf(self: Out, comptime fmt: []const u8, args: anytype) RuntimeError!void {
        try self.ctx.vm.output.print(self.ctx.allocator, fmt, args);
    }

    // php_info_print_table_start; table_end prints nothing in text mode
    fn tableStart(self: Out) RuntimeError!void {
        try self.print("\n");
    }

    // php_info_print_table_header: an empty cell is a space, followed by the
    // separator like any other
    fn header(self: Out, cells: []const []const u8) RuntimeError!void {
        for (cells, 0..) |cell, i| {
            try self.print(if (cell.len == 0) " " else cell);
            try self.print(if (i + 1 < cells.len) " => " else "\n");
        }
    }

    // php_info_print_table_row_internal: an empty cell prints a space and no
    // separator after it
    fn row(self: Out, cells: []const []const u8) RuntimeError!void {
        for (cells, 0..) |cell, i| {
            if (cell.len == 0) {
                try self.print(" ");
            } else {
                try self.print(cell);
                if (i + 1 < cells.len) try self.print(" => ");
            }
            if (i + 1 == cells.len) try self.print("\n");
        }
    }

    // SECTION(name)
    fn section(self: Out, name: []const u8) RuntimeError!void {
        try self.tableStart();
        try self.header(&.{name});
    }

    fn hr(self: Out) RuntimeError!void {
        try self.print("\n\n _______________________________________________________________________\n\n");
    }

    // php_info_print_table_colspan_header: printf("%*s%s%*s\n", spaces / 2,
    // " ", header, spaces / 2, " "), so a width below 2 still prints the one
    // space
    fn colspanHeader(self: Out, text: []const u8) RuntimeError!void {
        const spaces: i64 = 74 - @as(i64, @intCast(text.len));
        const half: usize = if (spaces > 0) @intCast(@divTrunc(spaces, 2)) else 0;
        try self.pad(half);
        try self.print(text);
        try self.pad(half);
        try self.print("\n");
    }

    fn pad(self: Out, width: usize) RuntimeError!void {
        var n = @max(width, 1);
        while (n > 0) : (n -= 1) try self.print(" ");
    }
};

const zend_version = std.fmt.comptimePrint("Zend Engine v4.{d}.{d}, Copyright © Zend by Perforce\n", .{ php_version.minor, php_version.release });
const api_version = "20250925";

pub fn printInfo(ctx: *NativeContext, flag: i64) RuntimeError!void {
    const out = Out{ .ctx = ctx };
    try out.print("phpinfo()\n");

    if (flag & INFO_GENERAL != 0) {
        try out.row(&.{ "PHP Version", php_version.string });
        try out.tableStart();
        const uname = try ctx.vm.callByName("php_uname", &.{});
        try out.row(&.{ "System", if (uname == .string) uname.string.bytes() else "" });
        try out.row(&.{ "Build Date", "Jan  1 1970 00:00:00" });
        try out.row(&.{ "Configure Command", " './configure' " });
        try out.row(&.{ "Server API", "Command Line Interface" });
        try out.row(&.{ "Virtual Directory Support", "disabled" });
        try out.row(&.{ "Configuration File (php.ini) Path", "" });
        try out.row(&.{ "Loaded Configuration File", ini_config.loadedFile() orelse "(none)" });
        try out.row(&.{ "Scan this dir for additional .ini files", "(none)" });
        try out.row(&.{ "Additional .ini files parsed", "(none)" });
        try out.row(&.{ "PHP API", api_version });
        try out.row(&.{ "PHP Extension", api_version });
        try out.row(&.{ "Zend Extension", "4" ++ api_version });
        try out.row(&.{ "Zend Extension Build", "API4" ++ api_version ++ ",NTS" });
        try out.row(&.{ "PHP Extension Build", "API" ++ api_version ++ ",NTS" });
        try out.row(&.{ "PHP Integer Size", "64 bits" });
        try out.row(&.{ "Debug Build", "no" });
        try out.row(&.{ "Thread Safety", "disabled" });
        try out.row(&.{ "Zend Signal Handling", "enabled" });
        try out.row(&.{ "Zend Memory Manager", "enabled" });
        try out.row(&.{ "Zend Multibyte Support", "provided by mbstring" });
        try out.row(&.{ "Zend Max Execution Timers", "disabled" });
        try out.row(&.{ "IPv6 Support", "enabled" });
        try out.row(&.{ "DTrace Support", "disabled" });
        try streamList(ctx, out, "PHP Streams", "stream_get_wrappers");
        try streamList(ctx, out, "Stream Socket Transports", "stream_get_transports");
        try streamList(ctx, out, "Stream Filters", "stream_get_filters");
        // php_info_print_box_start(0): a table start and a blank line
        try out.tableStart();
        try out.print("\n");
        try out.print("This program makes use of the Zend Scripting Language Engine:\n");
        try out.print(zend_version);
    }

    if (flag & INFO_CONFIGURATION != 0) {
        try out.hr();
        try out.section("Configuration");
        if (flag & INFO_MODULES == 0) {
            try out.section("PHP Core");
            try iniEntries(ctx, out, "Core");
        }
    }

    if (flag & INFO_MODULES != 0) try printModules(ctx, out);

    if (flag & INFO_ENVIRONMENT != 0) {
        try out.section("Environment");
        try out.tableStart();
        try out.header(&.{ "Variable", "Value" });
        if (platform.is_windows) {
            var map = platform.getEnvMap(ctx.allocator) catch return error.OutOfMemory;
            defer map.deinit();
            var it = map.iterator();
            while (it.next()) |e| try out.row(&.{ e.key_ptr.*, e.value_ptr.* });
        } else {
            var env: [*:null]const ?[*:0]const u8 = @ptrCast(std.c.environ);
            while (env[0]) |entry| : (env += 1) {
                const text = std.mem.sliceTo(entry, 0);
                const eq = std.mem.indexOfScalar(u8, text, '=') orelse continue;
                try out.row(&.{ text[0..eq], text[eq + 1 ..] });
            }
        }
    }

    if (flag & INFO_VARIABLES != 0) {
        try out.section("PHP Variables");
        try out.tableStart();
        try out.header(&.{ "Variable", "Value" });
        // global variables of these names, when the symbol table holds a
        // string directly: a variable the main script names is a compiled
        // slot, which the table only points to (IS_INDIRECT), so php skips it
        for ([_][]const u8{ "PHP_SELF", "PHP_AUTH_TYPE", "PHP_AUTH_USER", "PHP_AUTH_PW" }) |name| {
            var key_buf: [16]u8 = undefined;
            const key = std.fmt.bufPrint(&key_buf, "${s}", .{name}) catch unreachable;
            if (ctx.vm.frame_count == 0) break;
            const compiled = for (ctx.vm.global_slot_names) |sn| {
                if (std.mem.eql(u8, sn, key)) break true;
            } else false;
            if (compiled) continue;
            const v = ctx.vm.frames[0].vars.get(key) orelse continue;
            if (v == .string) try out.row(&.{ name, v.string.bytes() });
        }
        for ([_][]const u8{ "_REQUEST", "_GET", "_POST", "_FILES", "_COOKIE", "_SERVER", "_ENV" }) |name| try gpcseArray(ctx, out, name);
    }

    if (flag & INFO_CREDITS != 0) {
        try out.hr();
        try printCredits(ctx, CREDITS_ALL & ~CREDITS_FULLPAGE);
    }

    if (flag & INFO_LICENSE != 0) {
        try out.print("\n");
        try out.print("License\n");
        try out.print("\n");
        try out.print("PHP is free software. You may redistribute it and/or modify it under the\n");
        try out.print("terms of the Modified BSD License (SPDX-License-Identifier: BSD-3-Clause).\n");
        try out.print("\n");
        try out.print("Copyright © The PHP Group and Contributors.\n");
        try out.print("Copyright © Zend Technologies Ltd., a subsidiary company of\n");
        try out.print("    Perforce Software, Inc.\n");
        try out.print("\n");
        try out.print("Redistribution and use in source and binary forms, with or without\n");
        try out.print("modification, are permitted provided that the following conditions are met:\n");
        try out.print("\n");
        try out.print("1. Redistributions of source code must retain the above copyright notice, this\n");
        try out.print("   list of conditions and the following disclaimer.\n");
        try out.print("\n");
        try out.print("2. Redistributions in binary form must reproduce the above copyright notice,\n");
        try out.print("   this list of conditions and the following disclaimer in the documentation\n");
        try out.print("   and/or other materials provided with the distribution.\n");
        try out.print("\n");
        try out.print("3. Neither the name of the copyright holder nor the names of its\n");
        try out.print("   contributors may be used to endorse or promote products derived from\n");
        try out.print("   this software without specific prior written permission.\n");
        try out.print("\n");
        try out.print("THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS \"AS IS\"\n");
        try out.print("AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE\n");
        try out.print("IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE\n");
        try out.print("DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE\n");
        try out.print("FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL\n");
        try out.print("DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR\n");
        try out.print("SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER\n");
        try out.print("CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,\n");
        try out.print("OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE\n");
        try out.print("OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.\n");
    }
}

// php_info_print_stream_hash: the names joined on one row, no newline after
fn streamList(ctx: *NativeContext, out: Out, label: []const u8, func: []const u8) RuntimeError!void {
    const list = try ctx.vm.callByName(func, &.{});
    if (list != .array or list.array.entries.items.len == 0) {
        try out.printf("Registered {s} => none registered\n", .{label});
        return;
    }
    try out.printf("\nRegistered {s} => ", .{label});
    for (list.array.entries.items, 0..) |entry, i| {
        if (i > 0) try out.print(", ");
        if (entry.value == .string) try out.print(entry.value.string.bytes());
    }
}

// a cell of a module's information table: text, or a value read when printed
const Cell = union(enum) {
    text: []const u8,
    constant: []const u8,
    ini: []const u8,
    call: []const u8,
    hash_engines,
};

const Table = struct {
    rows: []const [2]?Cell = &.{},
    // php_info_print_box_start(0) text: a blank line, then the text without
    // a newline of its own
    box: ?[]const u8 = null,
};

const ModuleInfo = struct {
    name: []const u8,
    tables: []const Table,
    // modules whose MINFO doesn't call DISPLAY_INI_ENTRIES
    no_ini: bool = false,
};

fn t(s: []const u8) ?Cell {
    return .{ .text = s };
}

fn enabled(label: []const u8) [2]?Cell {
    return .{ t(label), t("enabled") };
}

// each extension's PHP_MINFO_FUNCTION, as far as zphp implements it
const module_infos = [_]ModuleInfo{
    .{ .name = "bcmath", .tables = &.{.{ .rows = &.{enabled("BCMath support")} }} },
    .{ .name = "ctype", .tables = &.{.{ .rows = &.{enabled("ctype functions")} }} },
    .{ .name = "curl", .tables = &.{.{ .rows = &.{enabled("cURL support")} }} },
    .{ .name = "date", .tables = &.{.{ .rows = &.{
        enabled("date/time support"),
        .{ t("timelib version"), t("2026.03") },
        .{ t("\"Olson\" Timezone Database Version"), .{ .call = "timezone_version_get" } },
        .{ t("Timezone Database"), t("internal") },
        .{ t("Default timezone"), .{ .call = "date_default_timezone_get" } },
    } }} },
    .{ .name = "dom", .tables = &.{.{ .rows = &.{
        enabled("DOM/XML"),
        .{ t("DOM/XML API Version"), t("20031129") },
        .{ t("libxml Version"), .{ .constant = "LIBXML_DOTTED_VERSION" } },
        enabled("HTML Support"),
        enabled("XPath Support"),
        enabled("XPointer Support"),
        enabled("Schema Support"),
        enabled("RelaxNG Support"),
    } }} },
    .{ .name = "fileinfo", .tables = &.{.{ .rows = &.{enabled("fileinfo support")} }} },
    .{ .name = "filter", .tables = &.{.{ .rows = &.{enabled("Input Validation and Filtering")} }} },
    .{ .name = "ftp", .tables = &.{.{ .rows = &.{ enabled("FTP support"), enabled("FTPS support") } }} },
    .{ .name = "gd", .tables = &.{.{ .rows = &.{
        enabled("GD Support"),
        .{ t("GD headers Version"), .{ .constant = "GD_VERSION" } },
        .{ t("GD library Version"), .{ .constant = "GD_VERSION" } },
    } }} },
    .{ .name = "gmp", .tables = &.{.{ .rows = &.{ enabled("gmp support"), .{ t("GMP version"), .{ .constant = "GMP_VERSION" } } } }} },
    .{ .name = "hash", .tables = &.{
        .{ .rows = &.{ enabled("hash support"), .{ t("Hashing Engines"), .hash_engines } } },
        .{ .rows = &.{ .{ t("MHASH support"), t("Enabled") }, .{ t("MHASH API Version"), t("Emulated Support") } } },
    } },
    .{ .name = "iconv", .tables = &.{.{ .rows = &.{
        enabled("iconv support"),
        .{ t("iconv implementation"), t("glibc") },
        .{ t("iconv library version"), .{ .constant = "ICONV_VERSION" } },
    } }} },
    .{ .name = "intl", .tables = &.{.{ .rows = &.{
        enabled("Internationalization support"),
        .{ t("ICU version"), .{ .constant = "INTL_ICU_VERSION" } },
    } }} },
    .{ .name = "json", .tables = &.{.{ .rows = &.{enabled("json support")} }} },
    .{ .name = "ldap", .tables = &.{.{ .rows = &.{enabled("LDAP Support")} }} },
    .{ .name = "libxml", .tables = &.{.{ .rows = &.{
        .{ t("libXML support"), t("active") },
        .{ t("libXML Compiled Version"), .{ .constant = "LIBXML_DOTTED_VERSION" } },
        .{ t("libXML Loaded Version"), .{ .constant = "LIBXML_VERSION" } },
        enabled("libXML streams"),
    } }} },
    .{ .name = "mbstring", .tables = &.{
        .{ .rows = &.{
            enabled("Multibyte Support"),
            .{ t("Multibyte string engine"), t("libmbfl") },
            .{ t("HTTP input encoding translation"), t("disabled") },
            .{ t("libmbfl version"), t("1.3.2") },
        } },
        .{ .rows = &.{.{ t("mbstring extension makes use of \"streamable kanji code filter and converter\", which is distributed under the GNU Lesser General Public License version 2.1."), null }} },
    } },
    .{ .name = "openssl", .tables = &.{.{ .rows = &.{
        enabled("OpenSSL support"),
        .{ t("OpenSSL Library Version"), .{ .constant = "OPENSSL_VERSION_TEXT" } },
        .{ t("OpenSSL Header Version"), .{ .constant = "OPENSSL_VERSION_TEXT" } },
    } }} },
    .{ .name = "pcntl", .tables = &.{.{ .rows = &.{enabled("pcntl support")} }} },
    .{ .name = "PDO", .tables = &.{.{ .rows = &.{ enabled("PDO support"), .{ t("PDO drivers"), t("mysql, pgsql, sqlite") } } }} },
    .{ .name = "pdo_mysql", .tables = &.{.{ .rows = &.{enabled("PDO Driver for MySQL")} }} },
    .{ .name = "pdo_pgsql", .tables = &.{.{ .rows = &.{enabled("PDO Driver for PostgreSQL")} }} },
    .{ .name = "pdo_sqlite", .tables = &.{.{ .rows = &.{enabled("PDO Driver for SQLite 3.x")} }} },
    .{ .name = "Phar", .tables = &.{
        .{ .rows = &.{
            enabled("Phar: PHP Archive support"),
            .{ t("Phar API version"), t("1.1.1") },
            enabled("Phar-based phar archives"),
            enabled("Tar-based phar archives"),
            enabled("ZIP-based phar archives"),
            enabled("gzip compression"),
            .{ t("bzip2 compression"), t("disabled (install ext/bz2)") },
            enabled("Native OpenSSL support"),
        } },
        .{ .box = "Phar based on pear/PHP_Archive, original concept by Davey Shafik.\nPhar fully realized by Gregory Beaver and Marcus Boerger.\nPortions of tar implementation Copyright (c) 2003-2009 Tim Kientzle." },
    } },
    .{ .name = "posix", .tables = &.{.{ .rows = &.{enabled("POSIX support")} }} },
    .{ .name = "Reflection", .tables = &.{.{ .rows = &.{enabled("Reflection")} }} },
    .{ .name = "session", .tables = &.{.{ .rows = &.{
        enabled("Session Support"),
        .{ t("Registered save handlers"), t("files user ") },
        .{ t("Registered serializer handlers"), t("php_serialize php php_binary ") },
    } }} },
    .{ .name = "SimpleXML", .tables = &.{.{ .rows = &.{ enabled("SimpleXML support"), enabled("Schema support") } }} },
    .{ .name = "soap", .tables = &.{.{ .rows = &.{ enabled("Soap Client"), enabled("Soap Server") } }} },
    .{ .name = "sodium", .tables = &.{.{ .rows = &.{
        enabled("sodium support"),
        .{ t("libsodium headers version"), .{ .constant = "SODIUM_LIBRARY_VERSION" } },
        .{ t("libsodium library version"), .{ .constant = "SODIUM_LIBRARY_VERSION" } },
    } }} },
    .{ .name = "SPL", .no_ini = true, .tables = &.{.{ .rows = &.{
        enabled("SPL support"),
        .{ t("Interfaces"), t("OuterIterator, RecursiveIterator, SeekableIterator, SplObserver, SplSubject") },
        .{ t("Classes"), t("AppendIterator, ArrayIterator, ArrayObject, BadFunctionCallException, BadMethodCallException, CachingIterator, CallbackFilterIterator, DirectoryIterator, DomainException, EmptyIterator, FilesystemIterator, FilterIterator, GlobIterator, InfiniteIterator, InvalidArgumentException, IteratorIterator, LengthException, LimitIterator, LogicException, MultipleIterator, NoRewindIterator, OutOfBoundsException, OutOfRangeException, OverflowException, ParentIterator, RangeException, RecursiveArrayIterator, RecursiveCachingIterator, RecursiveCallbackFilterIterator, RecursiveDirectoryIterator, RecursiveFilterIterator, RecursiveIteratorIterator, RecursiveRegexIterator, RecursiveTreeIterator, RegexIterator, RuntimeException, SplDoublyLinkedList, SplFileInfo, SplFileObject, SplFixedArray, SplHeap, SplMinHeap, SplMaxHeap, SplObjectStorage, SplPriorityQueue, SplQueue, SplStack, SplTempFileObject, UnderflowException, UnexpectedValueException") },
    } }} },
    .{ .name = "standard", .tables = &.{.{ .rows = &.{
        enabled("Dynamic Library Support"),
        .{ t("Path to sendmail"), .{ .ini = "sendmail_path" } },
    } }} },
    .{ .name = "tokenizer", .tables = &.{.{ .rows = &.{enabled("Tokenizer Support")} }} },
    .{ .name = "xml", .tables = &.{.{ .rows = &.{
        .{ t("XML Support"), t("active") },
        .{ t("XML Namespace Support"), t("active") },
        .{ t("libxml2 Version"), .{ .constant = "LIBXML_DOTTED_VERSION" } },
    } }} },
    .{ .name = "xmlreader", .tables = &.{.{ .rows = &.{enabled("XMLReader")} }} },
    .{ .name = "xmlwriter", .tables = &.{.{ .rows = &.{enabled("XMLWriter")} }} },
    .{ .name = "zlib", .tables = &.{.{ .rows = &.{
        enabled("ZLib Support"),
        .{ t("Stream Wrapper"), t("compress.zlib://") },
        .{ t("Stream Filter"), t("zlib.inflate, zlib.deflate") },
        .{ t("Compiled Version"), .{ .constant = "ZLIB_VERSION" } },
        .{ t("Linked Version"), .{ .constant = "ZLIB_VERSION" } },
    } }} },
};

fn lessIgnoreCase(_: void, a: []const u8, b: []const u8) bool {
    return std.ascii.lessThanIgnoreCase(a, b);
}

// the INFO_MODULES part: every module sorted by name (module_name_cmp),
// those with information first, then the ones without under "Additional
// Modules"
fn printModules(ctx: *NativeContext, out: Out) RuntimeError!void {
    const ext_mod = @import("../extension.zig");
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer names.deinit(ctx.allocator);
    try names.appendSlice(ctx.allocator, &types.SUPPORTED_EXTENSIONS);
    for (ext_mod.loaded()) |ext| try names.append(ctx.allocator, ext.name);
    std.mem.sort([]const u8, names.items, {}, lessIgnoreCase);

    for (names.items) |name| {
        if (nativeExtension(name)) |ext| if (ext.version.len == 0) continue;
        try printModuleSection(ctx, out, name);
    }

    try out.section("Additional Modules");
    try out.tableStart();
    try out.header(&.{"Module Name"});
    for (names.items) |name| {
        const ext = nativeExtension(name) orelse continue;
        if (ext.version.len == 0) try out.printf("{s}\n", .{name});
    }
}

// php_info_print_module for a module with information: its name, then its
// MINFO table or its version and directives
fn printModuleSection(ctx: *NativeContext, out: Out, name: []const u8) RuntimeError!void {
    if (nativeExtension(name)) |ext| {
        if (ext.version.len == 0) return out.printf("{s}\n", .{name});
        try out.section(name);
        try out.tableStart();
        try out.row(&.{ "Version", ext.version });
        return nativeExtensionIni(ctx, out, ext);
    }
    try out.section(name);
    if (std.mem.eql(u8, name, "Core")) {
        try out.tableStart();
        try out.row(&.{ "PHP Version", php_version.string });
        return iniEntries(ctx, out, name);
    }
    if (std.mem.eql(u8, name, "pcre")) {
        try @import("pcre.zig").writeInfoTable(ctx, &ctx.vm.output);
        return iniEntries(ctx, out, name);
    }
    const info = for (&module_infos) |*m| {
        if (std.mem.eql(u8, m.name, name)) break m;
    } else null;
    if (info) |m| {
        for (m.tables) |table| try printTable(ctx, out, table);
        if (!m.no_ini) try iniEntries(ctx, out, name);
    } else {
        // a module without an info function: its version and directives
        try out.tableStart();
        try out.row(&.{ "Version", php_version.string });
        try iniEntries(ctx, out, name);
    }
}

// php_info_print_module (ReflectionExtension::info, the cli's --ri) for a
// module by its declared name
pub fn printModule(ctx: *NativeContext, name: []const u8) RuntimeError!void {
    return printModuleSection(ctx, .{ .ctx = ctx, .sorted = false }, name);
}

// the cli's --ri main: display_ini_entries(NULL), the engine's directives
pub fn printMainIni(ctx: *NativeContext) RuntimeError!void {
    return iniEntries(ctx, .{ .ctx = ctx, .sorted = false }, "Core");
}

fn nativeExtension(name: []const u8) ?*@import("../extension.zig").Extension {
    for (types.SUPPORTED_EXTENSIONS) |builtin| if (std.mem.eql(u8, builtin, name)) return null;
    for (@import("../extension.zig").loaded()) |ext| if (std.mem.eql(u8, ext.name, name)) return ext;
    return null;
}

fn printTable(ctx: *NativeContext, out: Out, table: Table) RuntimeError!void {
    try out.tableStart();
    if (table.box) |text| {
        try out.print("\n");
        try out.print(text);
        return;
    }
    for (table.rows) |r| {
        var bufs: [2]std.ArrayListUnmanaged(u8) = .{ .empty, .empty };
        defer for (&bufs) |*b| b.deinit(ctx.allocator);
        var cells: [2][]const u8 = undefined;
        var n: usize = 0;
        for (r, 0..) |maybe, i| {
            const cell = maybe orelse break;
            try cellText(ctx, cell, &bufs[i]);
            cells[i] = bufs[i].items;
            n += 1;
        }
        try out.row(cells[0..n]);
    }
}

fn cellText(ctx: *NativeContext, cell: Cell, buf: *std.ArrayListUnmanaged(u8)) RuntimeError!void {
    const a = ctx.allocator;
    switch (cell) {
        .text => |s| try buf.appendSlice(a, s),
        .constant => |name| if (ctx.vm.php_constants.get(name)) |v| try v.format(buf, a),
        .ini => |name| if (iniLocal(ctx, name)) |v| try buf.appendSlice(a, v),
        .call => |name| {
            const v = try ctx.vm.callByName(name, &.{});
            if (v == .string) try buf.appendSlice(a, v.string.bytes());
        },
        // the algorithm names, each followed by a space
        .hash_engines => {
            const list = try ctx.vm.callByName("hash_algos", &.{});
            if (list == .array) for (list.array.entries.items) |entry| {
                if (entry.value != .string) continue;
                try buf.appendSlice(a, entry.value.string.bytes());
                try buf.append(a, ' ');
            };
        },
    }
}

fn iniLocal(ctx: *NativeContext, name: []const u8) ?[]const u8 {
    return ctx.vm.ini_settings.get(name) orelse ini_config.get(name) orelse types.iniDefault(name);
}

fn iniMaster(name: []const u8) ?[]const u8 {
    return ini_config.get(name) orelse types.iniDefault(name);
}

// directives shown through zend_ini_boolean_displayer_cb
const boolean_directives = [_][]const u8{
    "allow_url_fopen",               "allow_url_include",               "assert.active",                   "assert.bail",
    "assert.exception",              "assert.warning",                  "auto_detect_line_endings",        "auto_globals_jit",
    "display_startup_errors",        "enable_dl",                       "enable_post_data_reading",        "expose_php",
    "error_include_args",
    "fatal_error_backtraces",        "file_uploads",                    "gd.jpeg_ignore_warning",          "html_errors",
    "ignore_repeated_errors",        "ignore_repeated_source",          "ignore_user_abort",               "implicit_flush",
    "intl.use_exceptions",           "log_errors",                      "mail.add_x_header",               "mail.mixed_lf_and_crlf",
    "mbstring.encoding_translation", "mbstring.strict_detection",       "pcre.jit",                        "phar.readonly",
    "phar.require_hash",             "register_argc_argv",              "report_memleaks",                 "report_zend_debug",
    "session.auto_start",            "session.cookie_httponly",         "session.cookie_partitioned",      "session.cookie_secure",
    "session.lazy_write",            "session.upload_progress.cleanup", "session.upload_progress.enabled", "session.use_cookies",
    "session.use_only_cookies",      "session.use_strict_mode",         "session.use_trans_sid",           "short_open_tag",
    "sqlite3.defensive",             "xmlrpc_errors",                   "zend.detect_unicode",             "zend.enable_gc",
    "zend.exception_ignore_args",    "zend.multibyte",                  "zend.signal_check",               "zlib.output_compression",
};

fn isBooleanDirective(name: []const u8) bool {
    for (boolean_directives) |b| if (std.mem.eql(u8, b, name)) return true;
    return false;
}

// php_ini_displayer_cb and the displayers php's directives install
fn displayIni(out: Out, name: []const u8, value: ?[]const u8) RuntimeError!void {
    const v = value orelse "";
    if (isBooleanDirective(name)) {
        // zend_ini_parse_bool
        const on = std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "yes") or std.ascii.eqlIgnoreCase(v, "on") or atol(v) != 0;
        return out.print(if (on) "On" else "Off");
    }
    if (std.mem.eql(u8, name, "display_errors")) {
        // display_errors_mode: STDOUT or STDERR in the cli
        if (value == null) return out.print("STDOUT");
        if (std.ascii.eqlIgnoreCase(v, "on") or std.ascii.eqlIgnoreCase(v, "yes") or std.ascii.eqlIgnoreCase(v, "true") or std.ascii.eqlIgnoreCase(v, "stdout")) return out.print("STDOUT");
        if (std.ascii.eqlIgnoreCase(v, "stderr")) return out.print("STDERR");
        const mode: u8 = @truncate(@as(u64, @bitCast(atol(v))));
        return out.print(if (mode == 0) "Off" else if (mode == 2) "STDERR" else "STDOUT");
    }
    if (std.mem.startsWith(u8, name, "highlight.") and v.len > 0) {
        // zend_ini_color_displayer_cb
        return out.printf("<span style=\"color: {s}\">{s}</span>", .{ v, v });
    }
    try out.print(if (v.len == 0) "no value" else v);
}

// ZEND_ATOL: the leading integer
fn atol(s: []const u8) i64 {
    const trimmed = std.mem.trimStart(u8, s, " \t\n\r\x0b\x0c");
    var end: usize = 0;
    if (end < trimmed.len and (trimmed[end] == '-' or trimmed[end] == '+')) end += 1;
    while (end < trimmed.len and std.ascii.isDigit(trimmed[end])) end += 1;
    return std.fmt.parseInt(i64, trimmed[0..end], 10) catch 0;
}

// display_ini_entries(module): the module's directives, sorted when phpinfo() sorted them
fn iniEntries(ctx: *NativeContext, out: Out, module: []const u8) RuntimeError!void {
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer names.deinit(ctx.allocator);
    for (generated.ini) |entry| {
        if (std.ascii.eqlIgnoreCase(entry[1], module)) try names.append(ctx.allocator, entry[0]);
    }
    if (names.items.len == 0) return;
    if (out.sorted) std.mem.sort([]const u8, names.items, {}, lessIgnoreCase);
    try out.tableStart();
    try out.header(&.{ "Directive", "Local Value", "Master Value" });
    for (names.items) |name| {
        try out.print(name);
        try out.print(" => ");
        try displayIni(out, name, iniLocal(ctx, name));
        try out.print(" => ");
        try displayIni(out, name, iniMaster(name));
        try out.print("\n");
    }
}

fn nativeExtensionIni(ctx: *NativeContext, out: Out, ext: *@import("../extension.zig").Extension) RuntimeError!void {
    if (ext.inis.items.len == 0) return;
    try out.tableStart();
    try out.header(&.{ "Directive", "Local Value", "Master Value" });
    for (ext.inis.items) |entry| {
        try out.print(entry.name);
        try out.print(" => ");
        try displayIni(out, entry.name, ctx.vm.ini_settings.get(entry.name) orelse ini_config.get(entry.name) orelse entry.default);
        try out.print(" => ");
        try displayIni(out, entry.name, ini_config.get(entry.name) orelse entry.default);
        try out.print("\n");
    }
}

// php_print_gpcse_array
fn gpcseArray(ctx: *NativeContext, out: Out, name: []const u8) RuntimeError!void {
    var key_buf: [16]u8 = undefined;
    const key = std.fmt.bufPrint(&key_buf, "${s}", .{name}) catch unreachable;
    const cell = ctx.vm.globals_cells.get(key) orelse return;
    if (cell.* != .array) return;
    const arr = cell.*.array;
    for (arr.entries.items) |entry| {
        try out.printf("${s}['", .{name});
        switch (entry.key) {
            .int => |i| try out.printf("{d}", .{i}),
            .string => |s| try out.print(s.bytes()),
        }
        try out.print("'] => ");
        const v = if (entry.ref) |r| r.* else entry.value;
        if (v == .array) {
            // zend_print_zval_r
            try @import("output.zig").printRValueImpl(ctx.allocator, &ctx.vm.output, v, 0, ctx.vm);
        } else {
            // zval_get_tmp_string
            try out.print(try ctx.vm.valueToString(v));
        }
        try out.print("\n");
    }
}

const credits_sapi = [_][2][]const u8{
    .{ "Apache 2 Handler", "Ian Holsman, Justin Erenkrantz (based on Apache 2 Filter code)" },
    .{ "CGI / FastCGI", "Rasmus Lerdorf, Stig Bakken, Shane Caraveo, Dmitry Stogov" },
    .{ "CLI", "Edin Kadribasic, Marcus Boerger, Johannes Schlueter, Moriyoshi Koizumi, Xinchen Hui" },
    .{ "Embed", "Edin Kadribasic" },
    .{ "FastCGI Process Manager", "Andrei Nigmatulin, dreamcat4, Antony Dovgal, Jerome Loyet" },
    .{ "litespeed", "George Wang" },
    .{ "phpdbg", "Felipe Pena, Joe Watkins, Bob Weinand" },
};

// ext/standard/credits_ext.h
const credits_ext = [_][2][]const u8{
    .{ "BC Math", "Andi Gutmans" },
    .{ "Bzip2", "Sterling Hughes" },
    .{ "Calendar", "Shane Caraveo, Colin Viebrock, Hartmut Holzgraefe, Wez Furlong" },
    .{ "COM and .Net", "Wez Furlong" },
    .{ "ctype", "Hartmut Holzgraefe" },
    .{ "cURL", "Sterling Hughes" },
    .{ "Date/Time Support", "Derick Rethans" },
    .{ "DB-LIB (MS SQL, Sybase)", "Wez Furlong, Frank M. Kromann, Adam Baratz" },
    .{ "DBA", "Sascha Schumann, Marcus Boerger" },
    .{ "DOM", "Christian Stocker, Rob Richards, Marcus Boerger, Nora Dossche" },
    .{ "enchant", "Pierre-Alain Joye, Ilia Alshanetsky" },
    .{ "EXIF", "Rasmus Lerdorf, Marcus Boerger" },
    .{ "FFI", "Dmitry Stogov" },
    .{ "fileinfo", "Ilia Alshanetsky, Pierre Alain Joye, Scott MacVicar, Derick Rethans, Anatol Belski" },
    .{ "Firebird driver for PDO", "Ard Biesheuvel" },
    .{ "FTP", "Stefan Esser, Andrew Skalski" },
    .{ "GD imaging", "Rasmus Lerdorf, Stig Bakken, Jim Winstead, Jouni Ahto, Ilia Alshanetsky, Pierre-Alain Joye, Marcus Boerger, Mark Randall" },
    .{ "GetText", "Alex Plotnick" },
    .{ "GNU GMP support", "Stanislav Malyshev" },
    .{ "Iconv", "Rui Hirokawa, Stig Bakken, Moriyoshi Koizumi" },
    .{ "Input Filter", "Rasmus Lerdorf, Derick Rethans, Pierre-Alain Joye, Ilia Alshanetsky" },
    .{ "Internationalization", "Ed Batutis, Vladimir Iordanov, Dmitry Lakhtyuk, Stanislav Malyshev, Vadim Savchuk, Kirti Velankar" },
    .{ "JSON", "Jakub Zelenka, Omar Kilani, Scott MacVicar" },
    .{ "LDAP", "Amitay Isaacs, Eric Warnke, Rasmus Lerdorf, Gerrit Thomson, Stig Venaas" },
    .{ "LIBXML", "Christian Stocker, Rob Richards, Marcus Boerger, Wez Furlong, Shane Caraveo" },
    .{ "Multibyte String Functions", "Tsukada Takuya, Rui Hirokawa" },
    .{ "MySQL driver for PDO", "George Schlossnagle, Wez Furlong, Ilia Alshanetsky, Johannes Schlueter" },
    .{ "MySQLi", "Zak Greant, Georg Richter, Andrey Hristov, Ulf Wendel" },
    .{ "MySQLnd", "Andrey Hristov, Ulf Wendel, Georg Richter, Johannes Schlüter" },
    .{ "ODBC driver for PDO", "Wez Furlong" },
    .{ "ODBC", "Stig Bakken, Andreas Karajannis, Frank M. Kromann, Daniel R. Kalowsky" },
    .{ "Opcache", "Andi Gutmans, Zeev Suraski, Stanislav Malyshev, Dmitry Stogov, Xinchen Hui" },
    .{ "OpenSSL", "Stig Venaas, Wez Furlong, Sascha Kettler, Scott MacVicar, Eliot Lear" },
    .{ "pcntl", "Jason Greene, Arnaud Le Blanc" },
    .{ "Perl Compatible Regexps", "Andrei Zmievski" },
    .{ "PHP Archive", "Gregory Beaver, Marcus Boerger" },
    .{ "PHP Data Objects", "Wez Furlong, Marcus Boerger, Sterling Hughes, George Schlossnagle, Ilia Alshanetsky" },
    .{ "PHP hash", "Sara Golemon, Rasmus Lerdorf, Stefan Esser, Michael Wallner, Scott MacVicar" },
    .{ "Posix", "Kristian Koehntopp" },
    .{ "PostgreSQL driver for PDO", "Edin Kadribasic, Ilia Alshanetsky" },
    .{ "PostgreSQL", "Jouni Ahto, Zeev Suraski, Yasuo Ohgaki, Chris Kings-Lynne" },
    .{ "random", "Go Kudo, Tim Düsterhus, Guilliam Xavier, Christoph M. Becker, Jakub Zelenka, Bob Weinand, Máté Kocsis, and Original RNG implementators" },
    .{ "Readline", "Thies C. Arntzen" },
    .{ "Reflection", "Marcus Boerger, Timm Friebe, George Schlossnagle, Andrei Zmievski, Johannes Schlueter" },
    .{ "Sessions", "Sascha Schumann, Andrei Zmievski" },
    .{ "Shared Memory Operations", "Slava Poliakov, Ilia Alshanetsky" },
    .{ "SimpleXML", "Sterling Hughes, Marcus Boerger, Rob Richards" },
    .{ "SNMP", "Rasmus Lerdorf, Harrie Hazewinkel, Mike Jackson, Steven Lawrance, Johann Hanne, Boris Lytochkin" },
    .{ "SOAP", "Brad Lafountain, Shane Caraveo, Dmitry Stogov" },
    .{ "Sockets", "Chris Vandomelen, Sterling Hughes, Daniel Beulshausen, Jason Greene" },
    .{ "Sodium", "Frank Denis" },
    .{ "SPL", "Marcus Boerger, Etienne Kneuss" },
    .{ "SQLite 3.x driver for PDO", "Wez Furlong" },
    .{ "SQLite3", "Scott MacVicar, Ilia Alshanetsky, Brad Dewar" },
    .{ "System V Message based IPC", "Wez Furlong" },
    .{ "System V Semaphores", "Tom May" },
    .{ "System V Shared Memory", "Christian Cartus" },
    .{ "tidy", "John Coggeshall, Ilia Alshanetsky" },
    .{ "tokenizer", "Andrei Zmievski, Johannes Schlueter" },
    .{ "uri", "Máté Kocsis, Tim Düsterhus, Ignace Nyamagana Butera, Arnaud Le Blanc, Dennis Snell, Nora Dossche, Nicolas Grekas" },
    .{ "XML", "Stig Bakken, Thies C. Arntzen, Sterling Hughes" },
    .{ "XMLReader", "Rob Richards" },
    .{ "XMLWriter", "Rob Richards, Pierre-Alain Joye" },
    .{ "XSL", "Christian Stocker, Rob Richards" },
    .{ "Zip", "Pierre-Alain Joye, Remi Collet" },
    .{ "Zlib", "Rasmus Lerdorf, Stefan Roehrich, Zeev Suraski, Jade Nicoletti, Michael Wallner" },
};

pub fn printCredits(ctx: *NativeContext, flag: i64) RuntimeError!void {
    const out = Out{ .ctx = ctx };
    try out.print("PHP Credits\n");
    if (flag & CREDITS_GROUP != 0) {
        try out.tableStart();
        try out.colspanHeader("PHP Group");
        try out.row(&.{"Thies C. Arntzen, Stig Bakken, Shane Caraveo, Andi Gutmans, Rasmus Lerdorf, Sam Ruby, Sascha Schumann, Zeev Suraski, Jim Winstead, Andrei Zmievski"});
    }
    if (flag & CREDITS_GENERAL != 0) {
        try out.tableStart();
        try out.colspanHeader("Language Design & Concept");
        try out.row(&.{"Andi Gutmans, Rasmus Lerdorf, Zeev Suraski, Marcus Boerger"});
        try out.tableStart();
        try out.colspanHeader("PHP Authors");
        try out.header(&.{ "Contribution", "Authors" });
        for ([_][2][]const u8{
            .{ "Zend Scripting Language Engine", "Andi Gutmans, Zeev Suraski, Stanislav Malyshev, Marcus Boerger, Dmitry Stogov, Xinchen Hui, Nikita Popov" },
            .{ "Extension Module API", "Andi Gutmans, Zeev Suraski, Andrei Zmievski" },
            .{ "UNIX Build and Modularization", "Stig Bakken, Sascha Schumann, Jani Taskinen, Peter Kokot" },
            .{ "Windows Support", "Shane Caraveo, Zeev Suraski, Wez Furlong, Pierre-Alain Joye, Anatol Belski, Kalle Sommer Nielsen" },
            .{ "Server API (SAPI) Abstraction Layer", "Andi Gutmans, Shane Caraveo, Zeev Suraski" },
            .{ "Streams Abstraction Layer", "Wez Furlong, Sara Golemon" },
            .{ "PHP Data Objects Layer", "Wez Furlong, Marcus Boerger, Sterling Hughes, George Schlossnagle, Ilia Alshanetsky" },
            .{ "Output Handler", "Zeev Suraski, Thies C. Arntzen, Marcus Boerger, Michael Wallner" },
            .{ "Consistent 64 bit support", "Anthony Ferrara, Anatol Belski" },
        }) |line| try out.row(&line);
    }
    if (flag & CREDITS_SAPI != 0) {
        try out.tableStart();
        try out.colspanHeader("SAPI Modules");
        try out.header(&.{ "Contribution", "Authors" });
        for (credits_sapi) |line| try out.row(&line);
    }
    if (flag & CREDITS_MODULES != 0) {
        try out.tableStart();
        try out.colspanHeader("Module Authors");
        try out.header(&.{ "Module", "Authors" });
        for (credits_ext) |line| try out.row(&line);
    }
    if (flag & CREDITS_DOCS != 0) {
        try out.tableStart();
        try out.colspanHeader("PHP Documentation");
        for ([_][2][]const u8{
            .{ "Authors", "Mehdi Achour, Friedhelm Betz, Antony Dovgal, Nuno Lopes, Hannes Magnusson, Philip Olson, Georg Richter, Damien Seguy, Jakub Vrana, Adam Harvey" },
            .{ "Editor", "Peter Cowburn" },
            .{ "User Note Maintainers", "Daniel P. Brown, Thiago Henrique Pojda" },
            .{ "Other Contributors", "Previously active authors, editors and other contributors are listed in the manual." },
        }) |line| try out.row(&line);
    }
    if (flag & CREDITS_QA != 0) {
        try out.tableStart();
        try out.colspanHeader("PHP Quality Assurance Team");
        try out.row(&.{"Ilia Alshanetsky, Joerg Behrens, Antony Dovgal, Stefan Esser, Moriyoshi Koizumi, Magnus Maatta, Sebastian Nohn, Derick Rethans, Melvyn Sopacua, Pierre-Alain Joye, Dmitry Stogov, Felipe Pena, David Soria Parra, Stanislav Malyshev, Julien Pauli, Stephen Zarkos, Anatol Belski, Remi Collet, Ferenc Kovacs"});
    }
    if (flag & CREDITS_WEB != 0) {
        try out.tableStart();
        try out.colspanHeader("Websites and Infrastructure team");
        for ([_][2][]const u8{
            .{ "PHP Websites Team", "Rasmus Lerdorf, Hannes Magnusson, Philip Olson, Lukas Kahwe Smith, Pierre-Alain Joye, Kalle Sommer Nielsen, Peter Cowburn, Adam Harvey, Ferenc Kovacs, Levi Morrison" },
            .{ "Event Maintainers", "Damien Seguy, Daniel P. Brown" },
            .{ "Network Infrastructure", "Daniel P. Brown" },
            .{ "Windows Infrastructure", "Alex Schoenmaker" },
        }) |line| try out.row(&line);
    }
}
