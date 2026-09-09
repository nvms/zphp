const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const PhpObject = @import("../runtime/value.zig").PhpObject;
const vm_mod = @import("../runtime/vm.zig");
const VM = vm_mod.VM;
const NativeResult = vm_mod.NativeResult;
const NativeContext = vm_mod.NativeContext;
const ClassDef = vm_mod.ClassDef;

const Allocator = std.mem.Allocator;
const RuntimeError = error{ RuntimeError, OutOfMemory };

pub fn register(vm: *VM, a: Allocator) !void {
    // RecursiveIterator interface
    var rec_iter = vm_mod.InterfaceDef{ .name = "RecursiveIterator" };
    rec_iter.parent = "Iterator";
    try rec_iter.methods.append(a, "hasChildren");
    try rec_iter.methods.append(a, "getChildren");
    try vm.interfaces.put(a, "RecursiveIterator", rec_iter);

    // GeneratorWrapper: lets generators be passed where Iterator objects
    // are expected (FilterIterator, AppendIterator, etc.). Stores the
    // generator and forwards Iterator methods to it.
    var gw_def = ClassDef{ .name = "GeneratorWrapper" };
    try gw_def.interfaces.append(a, "Iterator");
    try gw_def.methods.put(a, "rewind", .{ .name = "rewind", .arity = 0 });
    try gw_def.methods.put(a, "current", .{ .name = "current", .arity = 0 });
    try gw_def.methods.put(a, "key", .{ .name = "key", .arity = 0 });
    try gw_def.methods.put(a, "next", .{ .name = "next", .arity = 0 });
    try gw_def.methods.put(a, "valid", .{ .name = "valid", .arity = 0 });
    try vm.classes.put(a, "GeneratorWrapper", gw_def);
    try vm.native_fns.put(a, "GeneratorWrapper::rewind", gwRewind);
    try vm.native_fns.put(a, "GeneratorWrapper::current", gwCurrent);
    try vm.native_fns.put(a, "GeneratorWrapper::key", gwKey);
    try vm.native_fns.put(a, "GeneratorWrapper::next", gwNext);
    try vm.native_fns.put(a, "GeneratorWrapper::valid", gwValid);

    // SplFileInfo
    var fi_def = ClassDef{ .name = "SplFileInfo" };
    for ([_][]const u8{
        "__construct", "getFilename", "getExtension", "getBasename",
        "getPathname", "getPath",     "getRealPath",  "getSize",
        "isDir",       "isFile",      "isLink",       "isReadable",
        "isWritable",  "getMTime",    "getCTime",     "getATime",
        "getType",     "__toString",  "openFile",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else if (std.mem.eql(u8, m, "openFile")) 1 else 0;
        try fi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "SplFileInfo", fi_def);

    try vm.native_fns.put(a, "SplFileInfo::__construct", fiConstruct);
    try vm.native_fns.put(a, "SplFileInfo::getFilename", fiGetFilename);
    try vm.native_fns.put(a, "SplFileInfo::getExtension", fiGetExtension);
    try vm.native_fns.put(a, "SplFileInfo::getBasename", fiGetBasename);
    try vm.native_fns.put(a, "SplFileInfo::getPathname", fiGetPathname);
    try vm.native_fns.put(a, "SplFileInfo::getPath", fiGetPath);
    try vm.native_fns.put(a, "SplFileInfo::getRealPath", fiGetRealPath);
    try vm.native_fns.put(a, "SplFileInfo::getSize", fiGetSize);
    try vm.native_fns.put(a, "SplFileInfo::isDir", fiIsDir);
    try vm.native_fns.put(a, "SplFileInfo::isFile", fiIsFile);
    try vm.native_fns.put(a, "SplFileInfo::isLink", fiIsLink);
    try vm.native_fns.put(a, "SplFileInfo::isReadable", fiIsReadable);
    try vm.native_fns.put(a, "SplFileInfo::isWritable", fiIsWritable);
    try vm.native_fns.put(a, "SplFileInfo::getMTime", fiGetMTime);
    try vm.native_fns.put(a, "SplFileInfo::getCTime", fiGetCTime);
    try vm.native_fns.put(a, "SplFileInfo::getATime", fiGetATime);
    try vm.native_fns.put(a, "SplFileInfo::getType", fiGetType);
    try vm.native_fns.put(a, "SplFileInfo::__toString", fiToString);
    try vm.native_fns.put(a, "SplFileInfo::openFile", fiOpenFile);

    // DirectoryIterator
    var di_def = ClassDef{ .name = "DirectoryIterator" };
    di_def.parent = "SplFileInfo";
    try di_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{
        "__construct", "rewind", "current", "key", "next", "valid", "isDot",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else 0;
        try di_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "DirectoryIterator", di_def);

    try vm.native_fns.put(a, "DirectoryIterator::__construct", diConstruct);
    try vm.native_fns.put(a, "DirectoryIterator::rewind", diRewind);
    try vm.native_fns.put(a, "DirectoryIterator::current", diCurrent);
    try vm.native_fns.put(a, "DirectoryIterator::key", diKey);
    try vm.native_fns.put(a, "DirectoryIterator::next", diNext);
    try vm.native_fns.put(a, "DirectoryIterator::valid", diValid);
    try vm.native_fns.put(a, "DirectoryIterator::isDot", diIsDot);

    // FilesystemIterator (DirectoryIterator with SKIP_DOTS by default)
    var fsi_def = ClassDef{ .name = "FilesystemIterator" };
    fsi_def.parent = "DirectoryIterator";
    try fsi_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{
        "__construct", "rewind", "current", "key", "next", "valid",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else 0;
        try fsi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try fsi_def.static_props.put(a, "CURRENT_AS_PATHNAME", .{ .int = 0x0020 });
    try fsi_def.static_props.put(a, "CURRENT_AS_FILEINFO", .{ .int = 0x0000 });
    try fsi_def.static_props.put(a, "CURRENT_AS_SELF", .{ .int = 0x0010 });
    try fsi_def.static_props.put(a, "KEY_AS_PATHNAME", .{ .int = 0x0000 });
    try fsi_def.static_props.put(a, "KEY_AS_FILENAME", .{ .int = 0x0100 });
    try fsi_def.static_props.put(a, "FOLLOW_SYMLINKS", .{ .int = 0x0200 });
    try fsi_def.static_props.put(a, "SKIP_DOTS", .{ .int = 0x1000 });
    try fsi_def.static_props.put(a, "UNIX_PATHS", .{ .int = 0x2000 });
    try vm.classes.put(a, "FilesystemIterator", fsi_def);
    try vm.native_fns.put(a, "FilesystemIterator::__construct", fsiConstruct);
    try vm.native_fns.put(a, "FilesystemIterator::rewind", diRewind);
    try vm.native_fns.put(a, "FilesystemIterator::current", diCurrent);
    try vm.native_fns.put(a, "FilesystemIterator::key", diKey);
    try vm.native_fns.put(a, "FilesystemIterator::next", diNext);
    try vm.native_fns.put(a, "FilesystemIterator::valid", diValid);

    // RecursiveDirectoryIterator
    var rdi_def = ClassDef{ .name = "RecursiveDirectoryIterator" };
    rdi_def.parent = "DirectoryIterator";
    try rdi_def.interfaces.append(a, "RecursiveIterator");
    for ([_][]const u8{
        "__construct", "hasChildren", "getChildren", "getSubPath", "getSubPathname",
        "rewind",      "current",     "key",         "next",       "valid",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else 0;
        try rdi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try rdi_def.static_props.put(a, "SKIP_DOTS", .{ .int = 0x1000 });
    try rdi_def.static_props.put(a, "FOLLOW_SYMLINKS", .{ .int = 0x0200 });
    try rdi_def.static_props.put(a, "CURRENT_AS_PATHNAME", .{ .int = 0x0020 });
    try rdi_def.static_props.put(a, "CURRENT_AS_SELF", .{ .int = 0x0010 });
    try rdi_def.static_props.put(a, "UNIX_PATHS", .{ .int = 0x2000 });
    try vm.classes.put(a, "RecursiveDirectoryIterator", rdi_def);

    try vm.native_fns.put(a, "RecursiveDirectoryIterator::__construct", rdiConstruct);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::hasChildren", rdiHasChildren);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::getChildren", rdiGetChildren);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::getSubPath", rdiGetSubPath);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::getSubPathname", rdiGetSubPathname);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::rewind", rdiRewind);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::current", rdiCurrent);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::key", rdiKey);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::next", rdiNext);
    try vm.native_fns.put(a, "RecursiveDirectoryIterator::valid", rdiValid);

    // FilterIterator (abstract - stores inner iterator, delegates with accept() filtering)
    var filter_def = ClassDef{ .name = "FilterIterator" };
    try filter_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{
        "__construct", "rewind", "current", "key", "next", "valid", "getInnerIterator",
        "getFilename", "isDir",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else 0;
        try filter_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "FilterIterator", filter_def);

    try vm.native_fns.put(a, "FilterIterator::__construct", filterConstruct);
    try vm.native_fns.put(a, "FilterIterator::rewind", filterRewind);
    try vm.native_fns.put(a, "FilterIterator::current", filterCurrent);
    try vm.native_fns.put(a, "FilterIterator::key", filterKey);
    try vm.native_fns.put(a, "FilterIterator::next", filterNext);
    try vm.native_fns.put(a, "FilterIterator::valid", filterValid);
    try vm.native_fns.put(a, "FilterIterator::getInnerIterator", filterGetInner);
    try vm.native_fns.put(a, "FilterIterator::getFilename", filterGetFilename);
    try vm.native_fns.put(a, "FilterIterator::isDir", filterIsDir);

    // RecursiveIteratorIterator
    var rii_def = ClassDef{ .name = "RecursiveIteratorIterator" };
    try rii_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{
        "__construct",      "rewind",         "current", "key", "next", "valid", "getDepth",
        "getInnerIterator", "getSubIterator",
    }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else 0;
        try rii_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try rii_def.static_props.put(a, "LEAVES_ONLY", .{ .int = 0 });
    try rii_def.static_props.put(a, "SELF_FIRST", .{ .int = 1 });
    try rii_def.static_props.put(a, "CHILD_FIRST", .{ .int = 2 });
    try vm.classes.put(a, "RecursiveIteratorIterator", rii_def);

    try rii_def.methods.put(a, "setMaxDepth", .{ .name = "setMaxDepth", .arity = 1 });
    try rii_def.methods.put(a, "getMaxDepth", .{ .name = "getMaxDepth", .arity = 0 });
    try vm.native_fns.put(a, "RecursiveIteratorIterator::__construct", riiConstruct);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::setMaxDepth", riiSetMaxDepth);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::getMaxDepth", riiGetMaxDepth);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::rewind", riiRewind);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::current", riiCurrent);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::key", riiKey);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::next", riiNext);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::valid", riiValid);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::getDepth", riiGetDepth);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::getInnerIterator", riiGetInner);
    try vm.native_fns.put(a, "RecursiveIteratorIterator::getSubIterator", riiGetSubIterator);

    // IteratorIterator (base wrapper - exposes Iterator interface for any inner iterator)
    var iter_def = ClassDef{ .name = "IteratorIterator" };
    try iter_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{ "__construct", "rewind", "valid", "current", "key", "next", "getInnerIterator" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else 0;
        try iter_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "IteratorIterator", iter_def);
    try vm.native_fns.put(a, "IteratorIterator::__construct", iiConstruct);
    try vm.native_fns.put(a, "IteratorIterator::rewind", iiRewind);
    try vm.native_fns.put(a, "IteratorIterator::valid", iiValid);
    try vm.native_fns.put(a, "IteratorIterator::current", iiCurrent);
    try vm.native_fns.put(a, "IteratorIterator::key", iiKey);
    try vm.native_fns.put(a, "IteratorIterator::next", iiNext);
    try vm.native_fns.put(a, "IteratorIterator::getInnerIterator", iiGetInner);

    // EmptyIterator
    var empty_def = ClassDef{ .name = "EmptyIterator" };
    try empty_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{ "rewind", "valid", "current", "key", "next" }) |m| {
        try empty_def.methods.put(a, m, .{ .name = m, .arity = 0 });
    }
    try vm.classes.put(a, "EmptyIterator", empty_def);
    try vm.native_fns.put(a, "EmptyIterator::rewind", emptyNoop);
    try vm.native_fns.put(a, "EmptyIterator::valid", emptyValid);
    try vm.native_fns.put(a, "EmptyIterator::current", emptyCurrent);
    try vm.native_fns.put(a, "EmptyIterator::key", emptyCurrent);
    try vm.native_fns.put(a, "EmptyIterator::next", emptyNoop);

    // LimitIterator (extends IteratorIterator behaviorally)
    var limit_def = ClassDef{ .name = "LimitIterator" };
    limit_def.parent = "IteratorIterator";
    for ([_][]const u8{ "__construct", "rewind", "valid", "current", "key", "next", "getPosition", "seek" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 3 else if (std.mem.eql(u8, m, "seek")) 1 else 0;
        try limit_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "LimitIterator", limit_def);
    try vm.native_fns.put(a, "LimitIterator::__construct", limitConstruct);
    try vm.native_fns.put(a, "LimitIterator::rewind", limitRewind);
    try vm.native_fns.put(a, "LimitIterator::valid", limitValid);
    try vm.native_fns.put(a, "LimitIterator::current", iiCurrent);
    try vm.native_fns.put(a, "LimitIterator::key", iiKey);
    try vm.native_fns.put(a, "LimitIterator::next", limitNext);
    try vm.native_fns.put(a, "LimitIterator::getPosition", limitGetPosition);
    try vm.native_fns.put(a, "LimitIterator::seek", limitSeek);

    // NoRewindIterator
    var nri_def = ClassDef{ .name = "NoRewindIterator" };
    nri_def.parent = "IteratorIterator";
    for ([_][]const u8{ "__construct", "rewind", "valid", "current", "key", "next" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else 0;
        try nri_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "NoRewindIterator", nri_def);
    try vm.native_fns.put(a, "NoRewindIterator::rewind", emptyNoop);

    // InfiniteIterator
    var inf_def = ClassDef{ .name = "InfiniteIterator" };
    inf_def.parent = "IteratorIterator";
    for ([_][]const u8{ "__construct", "rewind", "valid", "current", "key", "next" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 1 else 0;
        try inf_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "InfiniteIterator", inf_def);
    try vm.native_fns.put(a, "InfiniteIterator::next", infiniteNext);

    // AppendIterator
    var app_def = ClassDef{ .name = "AppendIterator" };
    try app_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{ "__construct", "append", "rewind", "valid", "current", "key", "next", "getInnerIterator", "getIteratorIndex", "getArrayIterator" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "append")) 1 else 0;
        try app_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "AppendIterator", app_def);
    try vm.native_fns.put(a, "AppendIterator::__construct", appConstruct);
    try vm.native_fns.put(a, "AppendIterator::append", appAppend);
    try vm.native_fns.put(a, "AppendIterator::rewind", appRewind);
    try vm.native_fns.put(a, "AppendIterator::valid", appValid);
    try vm.native_fns.put(a, "AppendIterator::current", appCurrent);
    try vm.native_fns.put(a, "AppendIterator::key", appKey);
    try vm.native_fns.put(a, "AppendIterator::next", appNext);
    try vm.native_fns.put(a, "AppendIterator::getInnerIterator", appGetInner);
    try vm.native_fns.put(a, "AppendIterator::getIteratorIndex", appGetIndex);
    try vm.native_fns.put(a, "AppendIterator::getArrayIterator", appGetArrayIterator);

    // CallbackFilterIterator
    var cbf_def = ClassDef{ .name = "CallbackFilterIterator" };
    cbf_def.parent = "FilterIterator";
    try cbf_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try cbf_def.methods.put(a, "accept", .{ .name = "accept", .arity = 0 });
    try vm.classes.put(a, "CallbackFilterIterator", cbf_def);
    try vm.native_fns.put(a, "CallbackFilterIterator::__construct", cbfConstruct);
    try vm.native_fns.put(a, "CallbackFilterIterator::accept", cbfAccept);

    // RegexIterator
    var rx_def = ClassDef{ .name = "RegexIterator" };
    rx_def.parent = "FilterIterator";
    for ([_][]const u8{ "__construct", "accept", "current", "getRegex", "getMode", "setMode", "getFlags", "setFlags", "getPregFlags", "setPregFlags" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 5 else if (std.mem.startsWith(u8, m, "set")) 1 else 0;
        try rx_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try rx_def.static_props.put(a, "MATCH", .{ .int = 0 });
    try rx_def.static_props.put(a, "GET_MATCH", .{ .int = 1 });
    try rx_def.static_props.put(a, "ALL_MATCHES", .{ .int = 2 });
    try rx_def.static_props.put(a, "SPLIT", .{ .int = 3 });
    try rx_def.static_props.put(a, "REPLACE", .{ .int = 4 });
    try rx_def.static_props.put(a, "USE_KEY", .{ .int = 1 });
    try rx_def.static_props.put(a, "INVERT_MATCH", .{ .int = 2 });
    try vm.classes.put(a, "RegexIterator", rx_def);
    try vm.native_fns.put(a, "RegexIterator::__construct", rxConstruct);
    try vm.native_fns.put(a, "RegexIterator::accept", rxAccept);
    try vm.native_fns.put(a, "RegexIterator::current", rxCurrent);
    try vm.native_fns.put(a, "RegexIterator::getRegex", rxGetRegex);
    try vm.native_fns.put(a, "RegexIterator::getMode", rxGetMode);
    try vm.native_fns.put(a, "RegexIterator::setMode", rxSetMode);
    try vm.native_fns.put(a, "RegexIterator::getFlags", rxGetFlags);
    try vm.native_fns.put(a, "RegexIterator::setFlags", rxSetFlags);
    try vm.native_fns.put(a, "RegexIterator::getPregFlags", rxGetPregFlags);
    try vm.native_fns.put(a, "RegexIterator::setPregFlags", rxSetPregFlags);

    // CachingIterator
    var ci_def = ClassDef{ .name = "CachingIterator" };
    ci_def.parent = "IteratorIterator";
    for ([_][]const u8{ "__construct", "rewind", "valid", "current", "key", "next", "hasNext", "__toString", "getCache", "getFlags", "setFlags" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else if (std.mem.eql(u8, m, "setFlags")) 1 else 0;
        try ci_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try ci_def.static_props.put(a, "CALL_TOSTRING", .{ .int = 1 });
    try ci_def.static_props.put(a, "CATCH_GET_CHILD", .{ .int = 2 });
    try ci_def.static_props.put(a, "TOSTRING_USE_KEY", .{ .int = 4 });
    try ci_def.static_props.put(a, "TOSTRING_USE_CURRENT", .{ .int = 8 });
    try ci_def.static_props.put(a, "TOSTRING_USE_INNER", .{ .int = 16 });
    try ci_def.static_props.put(a, "FULL_CACHE", .{ .int = 256 });
    try vm.classes.put(a, "CachingIterator", ci_def);
    try vm.native_fns.put(a, "CachingIterator::__construct", ciConstruct);
    try vm.native_fns.put(a, "CachingIterator::rewind", ciRewind);
    try vm.native_fns.put(a, "CachingIterator::valid", ciValid);
    try vm.native_fns.put(a, "CachingIterator::current", ciCurrent);
    try vm.native_fns.put(a, "CachingIterator::key", ciKey);
    try vm.native_fns.put(a, "CachingIterator::next", ciNext);
    try vm.native_fns.put(a, "CachingIterator::hasNext", ciHasNext);
    try vm.native_fns.put(a, "CachingIterator::__toString", ciToString);
    try vm.native_fns.put(a, "CachingIterator::getCache", ciGetCache);
    try vm.native_fns.put(a, "CachingIterator::getFlags", ciGetFlags);
    try vm.native_fns.put(a, "CachingIterator::setFlags", ciSetFlags);

    // MultipleIterator
    var mi_def = ClassDef{ .name = "MultipleIterator" };
    try mi_def.interfaces.append(a, "Iterator");
    for ([_][]const u8{ "__construct", "attachIterator", "detachIterator", "containsIterator", "countIterators", "rewind", "valid", "current", "key", "next", "getFlags", "setFlags" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "attachIterator")) 2 else if (std.mem.eql(u8, m, "detachIterator") or std.mem.eql(u8, m, "containsIterator") or std.mem.eql(u8, m, "setFlags")) 1 else 0;
        try mi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try mi_def.static_props.put(a, "MIT_NEED_ANY", .{ .int = 0 });
    try mi_def.static_props.put(a, "MIT_NEED_ALL", .{ .int = 1 });
    try mi_def.static_props.put(a, "MIT_KEYS_NUMERIC", .{ .int = 0 });
    try mi_def.static_props.put(a, "MIT_KEYS_ASSOC", .{ .int = 2 });
    try vm.classes.put(a, "MultipleIterator", mi_def);
    try vm.native_fns.put(a, "MultipleIterator::__construct", miConstruct);
    try vm.native_fns.put(a, "MultipleIterator::attachIterator", miAttach);
    try vm.native_fns.put(a, "MultipleIterator::detachIterator", miDetach);
    try vm.native_fns.put(a, "MultipleIterator::containsIterator", miContains);
    try vm.native_fns.put(a, "MultipleIterator::countIterators", miCountIterators);
    try vm.native_fns.put(a, "MultipleIterator::rewind", miRewind);
    try vm.native_fns.put(a, "MultipleIterator::valid", miValid);
    try vm.native_fns.put(a, "MultipleIterator::current", miCurrent);
    try vm.native_fns.put(a, "MultipleIterator::key", miKey);
    try vm.native_fns.put(a, "MultipleIterator::next", miNext);
    try vm.native_fns.put(a, "MultipleIterator::getFlags", miGetFlags);
    try vm.native_fns.put(a, "MultipleIterator::setFlags", miSetFlags);

    // RecursiveFilterIterator (abstract - extends FilterIterator + RecursiveIterator)
    var rfi_def = ClassDef{ .name = "RecursiveFilterIterator" };
    rfi_def.parent = "FilterIterator";
    try rfi_def.interfaces.append(a, "RecursiveIterator");
    try rfi_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 1 });
    try rfi_def.methods.put(a, "hasChildren", .{ .name = "hasChildren", .arity = 0 });
    try rfi_def.methods.put(a, "getChildren", .{ .name = "getChildren", .arity = 0 });
    try vm.classes.put(a, "RecursiveFilterIterator", rfi_def);
    try vm.native_fns.put(a, "RecursiveFilterIterator::hasChildren", rfiHasChildren);
    try vm.native_fns.put(a, "RecursiveFilterIterator::getChildren", rfiGetChildren);

    // RecursiveCallbackFilterIterator
    var rcbf_def = ClassDef{ .name = "RecursiveCallbackFilterIterator" };
    rcbf_def.parent = "RecursiveFilterIterator";
    try rcbf_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 2 });
    try rcbf_def.methods.put(a, "accept", .{ .name = "accept", .arity = 0 });
    try rcbf_def.methods.put(a, "hasChildren", .{ .name = "hasChildren", .arity = 0 });
    try rcbf_def.methods.put(a, "getChildren", .{ .name = "getChildren", .arity = 0 });
    try vm.classes.put(a, "RecursiveCallbackFilterIterator", rcbf_def);
    try vm.native_fns.put(a, "RecursiveCallbackFilterIterator::__construct", cbfConstruct);
    try vm.native_fns.put(a, "RecursiveCallbackFilterIterator::accept", cbfAccept);
    try vm.native_fns.put(a, "RecursiveCallbackFilterIterator::getChildren", rcbfGetChildren);

    // RecursiveRegexIterator
    var rrx_def = ClassDef{ .name = "RecursiveRegexIterator" };
    rrx_def.parent = "RegexIterator";
    try rrx_def.interfaces.append(a, "RecursiveIterator");
    try rrx_def.methods.put(a, "__construct", .{ .name = "__construct", .arity = 5 });
    try rrx_def.methods.put(a, "hasChildren", .{ .name = "hasChildren", .arity = 0 });
    try rrx_def.methods.put(a, "getChildren", .{ .name = "getChildren", .arity = 0 });
    try vm.classes.put(a, "RecursiveRegexIterator", rrx_def);
    try vm.native_fns.put(a, "RecursiveRegexIterator::hasChildren", rfiHasChildren);
    try vm.native_fns.put(a, "RecursiveRegexIterator::getChildren", rrxGetChildren);

    // RecursiveArrayIterator (extends ArrayIterator, adds hasChildren/getChildren)
    var rai_def = ClassDef{ .name = "RecursiveArrayIterator" };
    rai_def.parent = "ArrayIterator";
    try rai_def.interfaces.append(a, "RecursiveIterator");
    try rai_def.methods.put(a, "hasChildren", .{ .name = "hasChildren", .arity = 0 });
    try rai_def.methods.put(a, "getChildren", .{ .name = "getChildren", .arity = 0 });
    try vm.classes.put(a, "RecursiveArrayIterator", rai_def);
    try vm.native_fns.put(a, "RecursiveArrayIterator::hasChildren", raiHasChildren);
    try vm.native_fns.put(a, "RecursiveArrayIterator::getChildren", raiGetChildren);

    // RecursiveTreeIterator
    var rti_def = ClassDef{ .name = "RecursiveTreeIterator" };
    rti_def.parent = "RecursiveIteratorIterator";
    for ([_][]const u8{ "__construct", "current", "key", "getPrefix", "setPrefixPart", "getEntry", "getPostfix" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 4 else if (std.mem.eql(u8, m, "setPrefixPart")) 2 else 0;
        try rti_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try rti_def.static_props.put(a, "BYPASS_CURRENT", .{ .int = 4 });
    try rti_def.static_props.put(a, "BYPASS_KEY", .{ .int = 8 });
    try rti_def.static_props.put(a, "PREFIX_LEFT", .{ .int = 0 });
    try rti_def.static_props.put(a, "PREFIX_MID_HAS_NEXT", .{ .int = 1 });
    try rti_def.static_props.put(a, "PREFIX_MID_LAST", .{ .int = 2 });
    try rti_def.static_props.put(a, "PREFIX_END_HAS_NEXT", .{ .int = 3 });
    try rti_def.static_props.put(a, "PREFIX_END_LAST", .{ .int = 4 });
    try rti_def.static_props.put(a, "PREFIX_RIGHT", .{ .int = 5 });
    try vm.classes.put(a, "RecursiveTreeIterator", rti_def);
    try vm.native_fns.put(a, "RecursiveTreeIterator::__construct", rtiConstruct);
    try vm.native_fns.put(a, "RecursiveTreeIterator::current", rtiCurrent);
    try vm.native_fns.put(a, "RecursiveTreeIterator::getPrefix", rtiGetPrefix);
    try vm.native_fns.put(a, "RecursiveTreeIterator::getEntry", rtiGetEntry);
    try vm.native_fns.put(a, "RecursiveTreeIterator::getPostfix", rtiGetPostfix);

    // GlobIterator (extends DirectoryIterator behaviorally; backed by glob results)
    var gi_def = ClassDef{ .name = "GlobIterator" };
    gi_def.parent = "SplFileInfo";
    try gi_def.interfaces.append(a, "Iterator");
    try gi_def.interfaces.append(a, "Countable");
    for ([_][]const u8{ "__construct", "rewind", "valid", "current", "key", "next", "count" }) |m| {
        const arity: u8 = if (std.mem.eql(u8, m, "__construct")) 2 else 0;
        try gi_def.methods.put(a, m, .{ .name = m, .arity = arity });
    }
    try vm.classes.put(a, "GlobIterator", gi_def);
    try vm.native_fns.put(a, "GlobIterator::__construct", giConstruct);
    try vm.native_fns.put(a, "GlobIterator::rewind", giRewind);
    try vm.native_fns.put(a, "GlobIterator::valid", giValid);
    try vm.native_fns.put(a, "GlobIterator::current", giCurrent);
    try vm.native_fns.put(a, "GlobIterator::key", giKey);
    try vm.native_fns.put(a, "GlobIterator::next", giNext);
    try vm.native_fns.put(a, "GlobIterator::count", giCount);
}

// ==========================================
// helpers
// ==========================================

fn getThis(ctx: *NativeContext) ?*PhpObject {
    const v = ctx.vm.currentFrame().vars.get("$this") orelse return null;
    if (v != .object) return null;
    return v.object;
}

fn objGetStr(obj: *PhpObject, key: []const u8) []const u8 {
    const v = obj.get(key);
    if (v == .string) return v.string.bytes();
    return "";
}

fn objGetInt(obj: *PhpObject, key: []const u8) i64 {
    const v = obj.get(key);
    if (v == .int) return v.int;
    return 0;
}

fn createFileInfoObj(ctx: *NativeContext, pathname: []const u8) !*PhpObject {
    const obj = try ctx.createObject("SplFileInfo");
    const path = try Value.String.create(ctx.allocator, pathname);
    defer path.release();
    try obj.set(ctx.allocator, "__pathname", .{ .string = path });
    return obj;
}

fn basename(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
        return path[idx + 1 ..];
    }
    return path;
}

fn dirname(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '/')) |idx| {
        if (idx == 0) return "/";
        return path[0..idx];
    }
    return ".";
}

fn statPath(path: []const u8) ?std.fs.File.Stat {
    if (!std.fs.path.isAbsolute(path)) return std.fs.cwd().statFile(path) catch null;
    const file = std.fs.openFileAbsolute(path, .{}) catch {
        var dir = std.fs.openDirAbsolute(path, .{}) catch return null;
        defer dir.close();
        return dir.stat() catch null;
    };
    defer file.close();
    return file.stat() catch null;
}

// ==========================================
// SplFileInfo
// ==========================================

fn fiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__pathname", args[0]);
    return NativeResult.scalar(.null);
}

fn fiGetFilename(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const path = objGetStr(obj, "__pathname");
    return NativeResult.copyString(ctx.allocator, basename(path));
}

fn fiGetExtension(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const name = basename(objGetStr(obj, "__pathname"));
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
        return NativeResult.copyString(ctx.allocator, name[idx + 1 ..]);
    }
    return NativeResult.literal("");
}

fn fiGetBasename(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    var name = basename(objGetStr(obj, "__pathname"));
    if (args.len >= 1 and args[0] == .string) {
        const suffix = args[0].string.bytes();
        if (std.mem.endsWith(u8, name, suffix)) {
            name = name[0 .. name.len - suffix.len];
        }
    }
    return NativeResult.copyString(ctx.allocator, name);
}

fn fiGetPathname(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("__pathname"));
}

fn fiGetPath(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.copyString(ctx.allocator, dirname(objGetStr(obj, "__pathname")));
}

fn fiGetRealPath(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const path = objGetStr(obj, "__pathname");
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const real = std.fs.cwd().realpath(path, &buf) catch return NativeResult.scalar(.{ .bool = false });
    return NativeResult.copyString(ctx.allocator, real);
}

fn fiGetSize(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(stat.size) });
}

fn fiIsDir(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const path = objGetStr(obj, "__pathname");
    const stat = statPath(path) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = stat.kind == .directory });
}

fn fiIsFile(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const path = objGetStr(obj, "__pathname");
    const stat = statPath(path) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = stat.kind == .file });
}

fn fiIsLink(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const path = objGetStr(obj, "__pathname");
    const stat = statPath(path) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = stat.kind == .sym_link });
}

fn fiIsReadable(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn fiIsWritable(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = true });
}

fn fiGetMTime(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(@divTrunc(stat.mtime, std.time.ns_per_s)) });
}

fn fiGetCTime(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(@divTrunc(stat.ctime, std.time.ns_per_s)) });
}

fn fiGetATime(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = @intCast(@divTrunc(stat.atime, std.time.ns_per_s)) });
}

fn fiGetType(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("unknown");
    const stat = statPath(objGetStr(obj, "__pathname")) orelse return NativeResult.literal("unknown");
    return switch (stat.kind) {
        .directory => NativeResult.literal("dir"),
        .file => NativeResult.literal("file"),
        .sym_link => NativeResult.literal("link"),
        else => NativeResult.literal("unknown"),
    };
}

fn fiToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    return NativeResult.share(obj.get("__pathname"));
}

fn fiOpenFile(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const path = objGetStr(this, "__pathname");
    const mode: Value = if (args.len >= 1 and args[0] == .string) args[0] else .{ .string = Value.String.borrowed("r") };
    const obj = try ctx.createObject("SplFileObject");
    _ = try ctx.vm.callMethod(obj, "__construct", &.{ .{ .string = Value.String.borrowed(path) }, mode });
    return NativeResult.borrowed(.{ .object = obj });
}

// ==========================================
// DirectoryIterator
// ==========================================

fn diConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const path = args[0].string.bytes();
    try obj.set(ctx.allocator, "__di_path", args[0]);
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });

    const entries = try loadDirectoryEntries(ctx, path, 0);
    try obj.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

const SKIP_DOTS: i64 = 0x1000;

fn loadDirectoryEntries(ctx: *NativeContext, path: []const u8, flags: i64) RuntimeError!*PhpArray {
    const arr = try ctx.createArray();

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return arr;
    defer dir.close();

    const skip_dots = (flags & SKIP_DOTS) != 0;
    if (!skip_dots) {
        inline for (.{ ".", ".." }) |dot_name| {
            const dot_full = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ path, dot_name });
            const dot_full_owned = try Value.String.adopt(ctx.allocator, dot_full);
            defer dot_full_owned.release();
            const dot_entry = try ctx.createArray();
            try dot_entry.set(ctx.allocator, .{ .string = Value.String.borrowed("name") }, .{ .string = Value.String.borrowed(dot_name) });
            try dot_entry.set(ctx.allocator, .{ .string = Value.String.borrowed("path") }, .{ .string = dot_full_owned });
            try dot_entry.set(ctx.allocator, .{ .string = Value.String.borrowed("is_dir") }, .{ .bool = true });
            try arr.append(ctx.allocator, .{ .array = dot_entry });
        }
    }

    var iter = dir.iterate();
    while (iter.next() catch null) |entry| {
        if (skip_dots and (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, ".."))) continue;

        const full = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ path, entry.name });
        const full_owned = try Value.String.adopt(ctx.allocator, full);
        defer full_owned.release();

        const is_dir: bool = entry.kind == .directory;
        const entry_arr = try ctx.createArray();
        const name = try Value.String.create(ctx.allocator, entry.name);
        defer name.release();
        try entry_arr.set(ctx.allocator, .{ .string = Value.String.borrowed("name") }, .{ .string = name });
        try entry_arr.set(ctx.allocator, .{ .string = Value.String.borrowed("path") }, .{ .string = full_owned });
        try entry_arr.set(ctx.allocator, .{ .string = Value.String.borrowed("is_dir") }, .{ .bool = is_dir });

        try arr.append(ctx.allocator, .{ .array = entry_arr });
    }
    return arr;
}

fn syncCurrentEntry(ctx: *NativeContext, obj: *PhpObject) !void {
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return;
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return;
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return;
    const path_val = entry.array.get(.{ .string = Value.String.borrowed("path") });
    if (path_val == .string) {
        try obj.set(ctx.allocator, "__pathname", path_val);
    }
}

fn fsiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const path = args[0].string.bytes();
    try obj.set(ctx.allocator, "__di_path", args[0]);
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    // FilesystemIterator skips dots by default
    const entries = try loadDirectoryEntries(ctx, path, SKIP_DOTS);
    try obj.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

fn diRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

fn diCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    // PHP's DirectoryIterator::current() returns the iterator itself
    // so methods like isDot(), getFilename(), getPathname() work on $entry
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return NativeResult.scalar(.null);
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.borrowed(.{ .object = obj });
}

fn diKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__di_idx") });
}

fn diNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const idx = objGetInt(obj, "__di_idx");
    try obj.set(ctx.allocator, "__di_idx", .{ .int = idx + 1 });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

fn diValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return NativeResult.scalar(.{ .bool = false });
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    return NativeResult.scalar(.{ .bool = idx < entries.length() });
}

fn diIsDot(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return NativeResult.scalar(.{ .bool = false });
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return NativeResult.scalar(.{ .bool = false });
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return NativeResult.scalar(.{ .bool = false });
    const name = entry.array.get(.{ .string = Value.String.borrowed("name") });
    if (name != .string) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(.{ .bool = std.mem.eql(u8, name.string.bytes(), ".") or std.mem.eql(u8, name.string.bytes(), "..") });
}

// ==========================================
// RecursiveDirectoryIterator
// ==========================================

fn rdiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    const path = args[0].string.bytes();
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;

    try obj.set(ctx.allocator, "__di_path", args[0]);
    try obj.set(ctx.allocator, "__di_flags", .{ .int = flags });
    try obj.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    try obj.set(ctx.allocator, "__pathname", args[0]);
    try obj.set(ctx.allocator, "__rdi_root", args[0]);

    const entries = try loadDirectoryEntries(ctx, path, flags);
    try obj.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, obj);
    return NativeResult.scalar(.null);
}

fn rdiGetCurrentEntry(obj: *PhpObject) ?*PhpArray {
    const entries = if (obj.get("__di_entries") == .array) obj.get("__di_entries").array else return null;
    const idx: usize = @intCast(@max(0, objGetInt(obj, "__di_idx")));
    if (idx >= entries.length()) return null;
    const entry = entries.get(.{ .int = @intCast(idx) });
    if (entry != .array) return null;
    return entry.array;
}

fn rdiHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const is_dir = entry.get(.{ .string = Value.String.borrowed("is_dir") });
    return NativeResult.scalar(.{ .bool = is_dir == .bool and is_dir.bool });
}

fn rdiGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.scalar(.null);
    const path_val = entry.get(.{ .string = Value.String.borrowed("path") });
    if (path_val != .string) return NativeResult.scalar(.null);
    const flags = objGetInt(obj, "__di_flags");

    const child = try ctx.createObject(obj.class_name);
    try child.set(ctx.allocator, "__di_path", .{ .string = path_val.string });
    try child.set(ctx.allocator, "__di_flags", .{ .int = flags });
    try child.set(ctx.allocator, "__di_idx", .{ .int = 0 });
    try child.set(ctx.allocator, "__pathname", .{ .string = path_val.string });
    const root = obj.get("rootPath");
    if (root != .null) try child.set(ctx.allocator, "rootPath", root);
    const rdi_root = obj.get("__rdi_root");
    if (rdi_root != .null) try child.set(ctx.allocator, "__rdi_root", rdi_root);
    try child.set(ctx.allocator, "subPath", .null);

    const entries = try loadDirectoryEntries(ctx, path_val.string.bytes(), flags);
    try child.set(ctx.allocator, "__di_entries", .{ .array = entries });
    try syncCurrentEntry(ctx, child);

    return NativeResult.borrowed(.{ .object = child });
}

fn rdiGetSubPath(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    // subpath is relative path from root to current directory
    const path = objGetStr(obj, "__di_path");
    const root = objGetStr(obj, "__rdi_root");
    if (root.len > 0 and std.mem.startsWith(u8, path, root)) {
        var sub = path[root.len..];
        if (sub.len > 0 and sub[0] == '/') sub = sub[1..];
        return NativeResult.copyString(ctx.allocator, sub);
    }
    return NativeResult.literal("");
}

fn rdiGetSubPathname(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.literal("");
    const name = entry.get(.{ .string = Value.String.borrowed("name") });
    const sub_result = try rdiGetSubPath(ctx, &.{});
    const sub_path = sub_result.value;
    defer if (sub_path == .string) sub_path.string.release();
    if (sub_path != .string or sub_path.string.bytes().len == 0) {
        if (name == .string) return NativeResult.shareString(name.string);
        return NativeResult.literal("");
    }
    if (name != .string) return NativeResult.share(sub_path);
    const result = try std.fmt.allocPrint(ctx.allocator, "{s}/{s}", .{ sub_path.string.bytes(), name.string.bytes() });
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, result));
}

fn rdiRewind(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return diRewind(ctx, args);
}

fn rdiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const path_val = entry.get(.{ .string = Value.String.borrowed("path") });
    if (path_val != .string) return NativeResult.scalar(.null);
    const fi = try createFileInfoObj(ctx, path_val.string.bytes());
    return NativeResult.borrowed(.{ .object = fi });
}

fn rdiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    const entry = rdiGetCurrentEntry(obj) orelse return NativeResult.literal("");
    const path_val = entry.get(.{ .string = Value.String.borrowed("path") });
    if (path_val != .string) return NativeResult.literal("");
    return NativeResult.share(path_val);
}

fn rdiNext(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return diNext(ctx, args);
}

fn rdiValid(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    return diValid(ctx, args);
}

// ==========================================
// FilterIterator
// ==========================================

/// wrap a value into an iterator-protocol object. generators get wrapped in
/// GeneratorWrapper so the rest of the iterator infra can call rewind/current
/// /key/next/valid on them without special-casing every site.
fn wrapAsIterator(ctx: *NativeContext, v: Value) !Value {
    if (v == .object) return v;
    if (v == .generator) {
        const wrapper = try ctx.vm.allocator.create(PhpObject);
        wrapper.* = .{ .class_name = "GeneratorWrapper" };
        try ctx.vm.objects.append(ctx.vm.allocator, wrapper);
        try wrapper.set(ctx.allocator, "__gen", v);
        return .{ .object = wrapper };
    }
    return v;
}

fn gwGenerator(this: *PhpObject) ?*@import("../runtime/value.zig").Generator {
    const v = this.get("__gen");
    if (v != .generator) return null;
    return v.generator;
}

fn gwRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = gwGenerator(this) orelse return NativeResult.scalar(.null);
    if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);
    return NativeResult.scalar(.null);
}

fn gwCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = gwGenerator(this) orelse return NativeResult.scalar(.null);
    if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);
    return NativeResult.share(gen.current_value);
}

fn gwKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = gwGenerator(this) orelse return NativeResult.scalar(.null);
    if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);
    return NativeResult.share(gen.current_key);
}

fn gwNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.null);
    const gen = gwGenerator(this) orelse return NativeResult.scalar(.null);
    if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);
    try ctx.vm.resumeGenerator(gen, .null);
    return NativeResult.scalar(.null);
}

fn gwValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const this = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const gen = gwGenerator(this) orelse return NativeResult.scalar(.{ .bool = false });
    if (gen.state == .created) try ctx.vm.resumeGenerator(gen, .null);
    return NativeResult.scalar(.{ .bool = gen.state != .completed });
}

fn filterConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const inner = try wrapAsIterator(ctx, args[0]);
    if (inner != .object) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__fi_inner", inner);
    return NativeResult.scalar(.null);
}

fn filterGetInnerIterator(obj: *PhpObject) ?*PhpObject {
    const v = obj.get("__fi_inner");
    if (v == .object) return v.object;
    return null;
}

fn filterRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = filterGetInnerIterator(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(inner, "rewind", &.{});
    // advance to first accepted element
    try filterAdvanceToAccepted(ctx, obj, inner);
    return NativeResult.scalar(.null);
}

fn filterAdvanceToAccepted(ctx: *NativeContext, obj: *PhpObject, inner: *PhpObject) !void {
    while (true) {
        const valid = try ctx.vm.callMethod(inner, "valid", &.{});
        if (!valid.isTruthy()) break;
        const accepted = try ctx.vm.callMethod(obj, "accept", &.{});
        if (accepted.isTruthy()) break;
        _ = try ctx.vm.callMethod(inner, "next", &.{});
    }
}

fn filterCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = filterGetInnerIterator(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callMethod(inner, "current", &.{}));
}

fn filterKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = filterGetInnerIterator(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callMethod(inner, "key", &.{}));
}

fn filterNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = filterGetInnerIterator(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(inner, "next", &.{});
    try filterAdvanceToAccepted(ctx, obj, inner);
    return NativeResult.scalar(.null);
}

fn filterValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const inner = filterGetInnerIterator(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(try ctx.vm.callMethod(inner, "valid", &.{}));
}

fn filterGetInner(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = filterGetInnerIterator(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = inner });
}

fn filterGetFilename(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = filterGetInnerIterator(obj) orelse return NativeResult.scalar(.null);
    if (ctx.vm.hasMethod(inner.class_name, "getFilename")) return NativeResult.share(try ctx.vm.callMethod(inner, "getFilename", &.{}));
    const current = try ctx.vm.callMethod(inner, "current", &.{});
    return if (current == .object) NativeResult.share(try ctx.vm.callMethod(current.object, "getFilename", &.{})) else NativeResult.scalar(.null);
}

fn filterIsDir(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const inner = filterGetInnerIterator(obj) orelse return NativeResult.scalar(.{ .bool = false });
    if (ctx.vm.hasMethod(inner.class_name, "isDir")) return NativeResult.share(try ctx.vm.callMethod(inner, "isDir", &.{}));
    const current = try ctx.vm.callMethod(inner, "current", &.{});
    return if (current == .object) NativeResult.share(try ctx.vm.callMethod(current.object, "isDir", &.{})) else NativeResult.scalar(.{ .bool = false });
}

// ==========================================
// RecursiveIteratorIterator
// ==========================================

// stores a stack of iterators to flatten recursive iteration
// mode: 0=LEAVES_ONLY, 1=SELF_FIRST, 2=CHILD_FIRST

fn riiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const inner = try wrapAsIterator(ctx, args[0]);
    if (inner != .object) return NativeResult.scalar(.null);
    const mode: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;

    try obj.set(ctx.allocator, "__rii_mode", .{ .int = mode });
    try obj.set(ctx.allocator, "__rii_depth", .{ .int = 0 });

    // store iterator stack as an array of objects
    const stack = try ctx.createArray();
    try stack.append(ctx.allocator, inner);
    try obj.set(ctx.allocator, "__rii_stack", .{ .array = stack });
    try obj.set(ctx.allocator, "__rii_valid", .{ .bool = false });

    return NativeResult.scalar(.null);
}

fn riiGetStack(obj: *PhpObject) ?*PhpArray {
    const v = obj.get("__rii_stack");
    if (v == .array) return v.array;
    return null;
}

fn riiCurrentIterator(obj: *PhpObject) ?*PhpObject {
    const stack = riiGetStack(obj) orelse return null;
    if (stack.length() == 0) return null;
    const top = stack.get(.{ .int = @as(i64, @intCast(stack.length())) - 1 });
    if (top == .object) return top.object;
    return null;
}

fn riiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const stack = riiGetStack(obj) orelse return NativeResult.scalar(.null);

    // reset stack to just the root iterator
    if (stack.length() == 0) return NativeResult.scalar(.null);
    const root = stack.get(.{ .int = 0 });
    stack.entries.items.len = 0;
    stack.next_int_key = 0;
    try stack.append(ctx.allocator, root);
    try obj.set(ctx.allocator, "__rii_depth", .{ .int = 0 });

    if (root != .object) return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(root.object, "rewind", &.{});

    const valid = try ctx.vm.callMethod(root.object, "valid", &.{});
    try obj.set(ctx.allocator, "__rii_valid", valid);

    if (valid.isTruthy()) {
        const mode = objGetInt(obj, "__rii_mode");
        if (mode == 1) {
            // SELF_FIRST: current iterator valid, check if we can descend
            // but first yield the current item
        } else {
            // LEAVES_ONLY or CHILD_FIRST: descend into children first
            try riiDescend(ctx, obj);
        }
    }
    return NativeResult.scalar(.null);
}

fn riiDescend(ctx: *NativeContext, obj: *PhpObject) !void {
    const mode = objGetInt(obj, "__rii_mode");
    const stack = riiGetStack(obj) orelse return;

    while (true) {
        const iter_obj = riiCurrentIterator(obj) orelse return;
        const valid = try ctx.vm.callMethod(iter_obj, "valid", &.{});
        if (!valid.isTruthy()) return;

        const has_children = ctx.vm.callMethod(iter_obj, "hasChildren", &.{}) catch Value{ .bool = false };
        if (!has_children.isTruthy()) {
            if (mode == 1) {
                // SELF_FIRST: already yielding this item
            }
            return;
        }

        // honor setMaxDepth: stop descending if depth+1 > max
        const max_v = obj.get("__rii_max_depth");
        if (max_v == .int and max_v.int >= 0) {
            const cur_depth = objGetInt(obj, "__rii_depth");
            if (cur_depth + 1 > max_v.int) return;
        }

        const children = ctx.vm.callMethod(iter_obj, "getChildren", &.{}) catch return;
        if (children != .object) return;

        _ = try ctx.vm.callMethod(children.object, "rewind", &.{});
        const child_valid = try ctx.vm.callMethod(children.object, "valid", &.{});
        if (!child_valid.isTruthy()) return;

        try stack.append(ctx.allocator, children);
        const depth = objGetInt(obj, "__rii_depth");
        try obj.set(ctx.allocator, "__rii_depth", .{ .int = depth + 1 });

        if (mode == 1) {
            // SELF_FIRST: check if this child can descend further
            continue;
        }
    }
}

fn riiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iter_obj = riiCurrentIterator(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callMethod(iter_obj, "current", &.{}));
}

fn riiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iter_obj = riiCurrentIterator(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callMethod(iter_obj, "key", &.{}));
}

fn riiNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try riiAdvance(ctx, obj);
    return NativeResult.scalar(.null);
}

fn riiAdvance(ctx: *NativeContext, obj: *PhpObject) !void {
    const stack = riiGetStack(obj) orelse return;
    const mode = objGetInt(obj, "__rii_mode");

    if (mode == 1) {
        // SELF_FIRST: try to descend into children first
        const iter_obj = riiCurrentIterator(obj) orelse return;
        const max_v = obj.get("__rii_max_depth");
        const cur_depth = objGetInt(obj, "__rii_depth");
        const can_descend = !(max_v == .int and max_v.int >= 0 and cur_depth + 1 > max_v.int);
        const has_children = if (can_descend) ctx.vm.callMethod(iter_obj, "hasChildren", &.{}) catch Value{ .bool = false } else Value{ .bool = false };
        if (has_children.isTruthy()) {
            const children = ctx.vm.callMethod(iter_obj, "getChildren", &.{}) catch {
                try riiAdvanceFlat(ctx, obj, stack);
                return;
            };
            if (children == .object) {
                _ = try ctx.vm.callMethod(children.object, "rewind", &.{});
                const child_valid = try ctx.vm.callMethod(children.object, "valid", &.{});
                if (child_valid.isTruthy()) {
                    try stack.append(ctx.allocator, children);
                    const depth = objGetInt(obj, "__rii_depth");
                    try obj.set(ctx.allocator, "__rii_depth", .{ .int = depth + 1 });
                    try obj.set(ctx.allocator, "__rii_valid", .{ .bool = true });
                    return;
                }
            }
        }
    }

    try riiAdvanceFlat(ctx, obj, stack);
}

fn riiAdvanceFlat(ctx: *NativeContext, obj: *PhpObject, stack: *PhpArray) !void {
    advance: while (stack.length() > 0) {
        const iter_val = stack.get(.{ .int = @as(i64, @intCast(stack.length())) - 1 });
        if (iter_val != .object) break;
        _ = try ctx.vm.callMethod(iter_val.object, "next", &.{});
        const valid = try ctx.vm.callMethod(iter_val.object, "valid", &.{});
        if (valid.isTruthy()) {
            try obj.set(ctx.allocator, "__rii_valid", .{ .bool = true });
            const mode = objGetInt(obj, "__rii_mode");
            if (mode != 1) try riiDescend(ctx, obj);
            // LEAVES_ONLY: skip arrays we couldn't descend into
            if (mode == 0) {
                if (riiCurrentIterator(obj)) |it| {
                    const cur_v = try ctx.vm.callMethod(it, "current", &.{});
                    if (cur_v == .array) continue :advance;
                }
            }
            return;
        }
        if (stack.entries.items.len > 1) {
            stack.entries.items.len -= 1;
            stack.next_int_key -= 1;
            const depth = objGetInt(obj, "__rii_depth");
            try obj.set(ctx.allocator, "__rii_depth", .{ .int = @max(0, depth - 1) });
        } else {
            break;
        }
    }
    try obj.set(ctx.allocator, "__rii_valid", .{ .bool = false });
}

fn riiValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(obj.get("__rii_valid"));
}

fn riiSetMaxDepth(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const v: i64 = if (args.len >= 1) Value.toInt(args[0]) else -1;
    try obj.set(ctx.allocator, "__rii_max_depth", .{ .int = v });
    return NativeResult.scalar(.{ .bool = true });
}

fn riiGetMaxDepth(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = obj.get("__rii_max_depth");
    if (v == .int and v.int < 0) return NativeResult.scalar(.{ .bool = false });
    if (v == .null) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.scalar(v);
}

fn riiGetDepth(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__rii_depth") });
}

fn riiGetInner(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iter_obj = riiCurrentIterator(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = iter_obj });
}

fn riiGetSubIterator(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const stack = riiGetStack(obj) orelse return NativeResult.scalar(.null);
    const depth: usize = if (args.len >= 1) @intCast(@max(0, Value.toInt(args[0]))) else @intCast(@max(0, objGetInt(obj, "__rii_depth")));
    if (depth >= stack.length()) return NativeResult.scalar(.null);
    return NativeResult.borrowed(stack.get(.{ .int = @intCast(depth) }));
}

// ==========================================
// IteratorIterator
// ==========================================

fn iiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    var inner = try wrapAsIterator(ctx, args[0]);
    // unwrap IteratorAggregate chains (PHP follows getIterator until it reaches
    // a real Iterator; depth-limit guards against runaway recursion)
    var depth: u8 = 0;
    while (inner == .object and depth < 8) : (depth += 1) {
        if (ctx.vm.isInstanceOf(inner.object.class_name, "Iterator")) break;
        if (!ctx.vm.isInstanceOf(inner.object.class_name, "IteratorAggregate")) break;
        inner = try ctx.vm.callMethod(inner.object, "getIterator", &.{});
    }
    if (inner != .object) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__ii_inner", inner);
    return NativeResult.scalar(.null);
}

fn iiGetInnerObj(obj: *PhpObject) ?*PhpObject {
    const v = obj.get("__ii_inner");
    if (v == .object) return v.object;
    return null;
}

fn iiRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(inner, "rewind", &.{});
    return NativeResult.scalar(.null);
}

fn iiValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(try ctx.vm.callMethod(inner, "valid", &.{}));
}

fn iiCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callMethod(inner, "current", &.{}));
}

fn iiKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callMethod(inner, "key", &.{}));
}

fn iiNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(inner, "next", &.{});
    return NativeResult.scalar(.null);
}

fn iiGetInner(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = inner });
}

// ==========================================
// EmptyIterator
// ==========================================

fn emptyNoop(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

fn emptyValid(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.{ .bool = false });
}

fn emptyCurrent(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.scalar(.null);
}

// ==========================================
// LimitIterator
// ==========================================

fn limitConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const inner = try wrapAsIterator(ctx, args[0]);
    if (inner != .object) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__ii_inner", inner);
    const offset: i64 = if (args.len >= 2) Value.toInt(args[1]) else 0;
    const count: i64 = if (args.len >= 3) Value.toInt(args[2]) else -1;
    try obj.set(ctx.allocator, "__li_offset", .{ .int = offset });
    try obj.set(ctx.allocator, "__li_count", .{ .int = count });
    try obj.set(ctx.allocator, "__li_pos", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn limitRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(inner, "rewind", &.{});
    const offset = objGetInt(obj, "__li_offset");
    var i: i64 = 0;
    while (i < offset) : (i += 1) {
        const valid = try ctx.vm.callMethod(inner, "valid", &.{});
        if (!valid.isTruthy()) break;
        _ = try ctx.vm.callMethod(inner, "next", &.{});
    }
    try obj.set(ctx.allocator, "__li_pos", .{ .int = offset });
    return NativeResult.scalar(.null);
}

fn limitValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.{ .bool = false });
    const count = objGetInt(obj, "__li_count");
    const offset = objGetInt(obj, "__li_offset");
    const pos = objGetInt(obj, "__li_pos");
    if (count >= 0 and (pos - offset) >= count) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(try ctx.vm.callMethod(inner, "valid", &.{}));
}

fn limitNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(inner, "next", &.{});
    try obj.set(ctx.allocator, "__li_pos", .{ .int = objGetInt(obj, "__li_pos") + 1 });
    return NativeResult.scalar(.null);
}

fn limitGetPosition(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__li_pos") });
}

fn limitSeek(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const target = Value.toInt(args[0]);
    const offset = objGetInt(obj, "__li_offset");
    const count = objGetInt(obj, "__li_count");
    if (target < offset or (count >= 0 and target >= offset + count)) return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    const cur = objGetInt(obj, "__li_pos");
    if (target < cur) {
        _ = try limitRewind(ctx, &.{});
    }
    while (objGetInt(obj, "__li_pos") < target) {
        const valid = try ctx.vm.callMethod(inner, "valid", &.{});
        if (!valid.isTruthy()) break;
        _ = try ctx.vm.callMethod(inner, "next", &.{});
        try obj.set(ctx.allocator, "__li_pos", .{ .int = objGetInt(obj, "__li_pos") + 1 });
    }
    return NativeResult.scalar(.null);
}

// ==========================================
// InfiniteIterator
// ==========================================

fn infiniteNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(inner, "next", &.{});
    const valid = try ctx.vm.callMethod(inner, "valid", &.{});
    if (!valid.isTruthy()) {
        _ = try ctx.vm.callMethod(inner, "rewind", &.{});
    }
    return NativeResult.scalar(.null);
}

// ==========================================
// AppendIterator
// ==========================================

fn appConstruct(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const arr = try ctx.createArray();
    try obj.set(ctx.allocator, "__app_iters", .{ .array = arr });
    try obj.set(ctx.allocator, "__app_idx", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn appGetIters(obj: *PhpObject) ?*PhpArray {
    const v = obj.get("__app_iters");
    if (v == .array) return v.array;
    return null;
}

fn appAppend(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const inner = try wrapAsIterator(ctx, args[0]);
    if (inner != .object) return NativeResult.scalar(.null);
    const iters = appGetIters(obj) orelse return NativeResult.scalar(.null);
    try iters.append(ctx.allocator, inner);
    // if this is the first iterator and we haven't started, rewind it
    if (iters.length() == 1) {
        _ = try ctx.vm.callMethod(inner.object, "rewind", &.{});
    }
    return NativeResult.scalar(.null);
}

fn appCurrentIter(obj: *PhpObject) ?*PhpObject {
    const iters = appGetIters(obj) orelse return null;
    const idx = objGetInt(obj, "__app_idx");
    if (idx < 0 or idx >= iters.length()) return null;
    const v = iters.get(.{ .int = idx });
    if (v == .object) return v.object;
    return null;
}

fn appRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__app_idx", .{ .int = 0 });
    const iter = appCurrentIter(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(iter, "rewind", &.{});
    return NativeResult.scalar(.null);
}

fn appValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const iters = appGetIters(obj) orelse return NativeResult.scalar(.{ .bool = false });
    while (true) {
        const idx = objGetInt(obj, "__app_idx");
        if (idx < 0 or idx >= iters.length()) return NativeResult.scalar(.{ .bool = false });
        const v = iters.get(.{ .int = idx });
        if (v != .object) return NativeResult.scalar(.{ .bool = false });
        const valid = try ctx.vm.callMethod(v.object, "valid", &.{});
        if (valid.isTruthy()) return NativeResult.scalar(.{ .bool = true });
        try obj.set(ctx.allocator, "__app_idx", .{ .int = idx + 1 });
        if (idx + 1 < iters.length()) {
            const nxt = iters.get(.{ .int = idx + 1 });
            if (nxt == .object) {
                _ = try ctx.vm.callMethod(nxt.object, "rewind", &.{});
            }
        }
    }
}

fn appCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iter = appCurrentIter(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callMethod(iter, "current", &.{}));
}

fn appKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iter = appCurrentIter(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.share(try ctx.vm.callMethod(iter, "key", &.{}));
}

fn appNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iter = appCurrentIter(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(iter, "next", &.{});
    return NativeResult.scalar(.null);
}

fn appGetInner(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iter = appCurrentIter(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .object = iter });
}

fn appGetIndex(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__app_idx") });
}

fn appGetArrayIterator(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters = appGetIters(obj) orelse return NativeResult.scalar(.null);
    return NativeResult.borrowed(.{ .array = iters });
}

// ==========================================
// CallbackFilterIterator
// ==========================================

fn cbfConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const inner = try wrapAsIterator(ctx, args[0]);
    if (inner != .object) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__fi_inner", inner);
    if (args.len >= 2) try obj.set(ctx.allocator, "__cb_fn", args[1]);
    return NativeResult.scalar(.null);
}

fn cbfAccept(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const cb = obj.get("__cb_fn");
    if (cb == .null) return NativeResult.scalar(.{ .bool = false });
    const inner_v = obj.get("__fi_inner");
    if (inner_v != .object) return NativeResult.scalar(.{ .bool = false });
    const cur = try ctx.vm.callMethod(inner_v.object, "current", &.{});
    const key = try ctx.vm.callMethod(inner_v.object, "key", &.{});
    const result = try ctx.invokeCallable(cb, &.{ cur, key, inner_v });
    return NativeResult.scalar(.{ .bool = result.isTruthy() });
}

// ==========================================
// RegexIterator
// ==========================================

fn rxConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const inner = try wrapAsIterator(ctx, args[0]);
    if (inner != .object) return NativeResult.scalar(.null);
    if (args.len < 2 or args[1] != .string) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__fi_inner", inner);
    try obj.set(ctx.allocator, "__rx_regex", args[1]);
    const mode: i64 = if (args.len >= 3) Value.toInt(args[2]) else 0;
    const flags: i64 = if (args.len >= 4) Value.toInt(args[3]) else 0;
    const preg_flags: i64 = if (args.len >= 5) Value.toInt(args[4]) else 0;
    try obj.set(ctx.allocator, "__rx_mode", .{ .int = mode });
    try obj.set(ctx.allocator, "__rx_flags", .{ .int = flags });
    try obj.set(ctx.allocator, "__rx_preg_flags", .{ .int = preg_flags });
    return NativeResult.scalar(.null);
}

fn rxSubjectFromInner(ctx: *NativeContext, obj: *PhpObject) RuntimeError!?Value.String {
    const inner_v = obj.get("__fi_inner");
    if (inner_v != .object) return null;
    const flags = objGetInt(obj, "__rx_flags");
    const subject_val = if ((flags & 1) != 0)
        try ctx.vm.callMethod(inner_v.object, "key", &.{})
    else
        try ctx.vm.callMethod(inner_v.object, "current", &.{});
    if (subject_val == .string) {
        subject_val.string.retain();
        return subject_val.string;
    }
    if (subject_val == .int or subject_val == .float or subject_val == .bool) {
        var buf: std.ArrayListUnmanaged(u8) = .{};
        defer buf.deinit(ctx.allocator);
        try subject_val.format(&buf, ctx.allocator);
        return try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator));
    }
    return null;
}

fn rxAccept(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const regex = objGetStr(obj, "__rx_regex");
    if (regex.len == 0) return NativeResult.scalar(.{ .bool = false });
    // arrays pass through so recursive variants can descend into them
    const inner_v = obj.get("__fi_inner");
    if (inner_v == .object) {
        const flags_check = objGetInt(obj, "__rx_flags");
        if ((flags_check & 1) == 0) {
            const cur_check = try ctx.vm.callMethod(inner_v.object, "current", &.{});
            if (cur_check == .array) return NativeResult.scalar(.{ .bool = true });
        }
    }
    const subject = (try rxSubjectFromInner(ctx, obj)) orelse return NativeResult.scalar(.{ .bool = false });
    defer subject.release();
    const flags = objGetInt(obj, "__rx_flags");
    const invert = (flags & 2) != 0;

    const matches_arr = try ctx.createArray();
    const result = try ctx.vm.callByName("preg_match", &.{ .{ .string = Value.String.borrowed(regex) }, .{ .string = subject }, .{ .array = matches_arr } });
    const matched = result == .int and result.int == 1;
    try obj.set(ctx.allocator, "__rx_match", .{ .array = matches_arr });
    return NativeResult.scalar(.{ .bool = if (invert) !matched else matched });
}

fn rxCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner_v = obj.get("__fi_inner");
    if (inner_v != .object) return NativeResult.scalar(.null);
    const mode = objGetInt(obj, "__rx_mode");
    if (mode == 0) {
        return NativeResult.share(try ctx.vm.callMethod(inner_v.object, "current", &.{}));
    }
    if (mode == 1) {
        const m = obj.get("__rx_match");
        if (m == .array) return NativeResult.borrowed(m);
        return NativeResult.scalar(.null);
    }
    if (mode == 2 or mode == 3) {
        const subject = (try rxSubjectFromInner(ctx, obj)) orelse return NativeResult.scalar(.null);
        defer subject.release();
        const regex = objGetStr(obj, "__rx_regex");
        if (mode == 3) {
            return NativeResult.share(try ctx.vm.callByName("preg_split", &.{ .{ .string = Value.String.borrowed(regex) }, .{ .string = subject } }));
        } else {
            const out_arr = try ctx.createArray();
            _ = try ctx.vm.callByName("preg_match_all", &.{ .{ .string = Value.String.borrowed(regex) }, .{ .string = subject }, .{ .array = out_arr } });
            return NativeResult.borrowed(.{ .array = out_arr });
        }
    }
    return NativeResult.share(try ctx.vm.callMethod(inner_v.object, "current", &.{}));
}

fn rxGetRegex(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    return NativeResult.share(obj.get("__rx_regex"));
}

fn rxGetMode(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__rx_mode") });
}

fn rxSetMode(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__rx_mode", .{ .int = Value.toInt(args[0]) });
    return NativeResult.scalar(.null);
}

fn rxGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__rx_flags") });
}

fn rxSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__rx_flags", .{ .int = Value.toInt(args[0]) });
    return NativeResult.scalar(.null);
}

fn rxGetPregFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__rx_preg_flags") });
}

fn rxSetPregFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__rx_preg_flags", .{ .int = Value.toInt(args[0]) });
    return NativeResult.scalar(.null);
}

// ==========================================
// CachingIterator
// ==========================================

fn ciConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    const inner = try wrapAsIterator(ctx, args[0]);
    if (inner != .object) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__ii_inner", inner);
    const flags: i64 = if (args.len >= 2) Value.toInt(args[1]) else 1;
    try obj.set(ctx.allocator, "__ci_flags", .{ .int = flags });
    const cache = try ctx.createArray();
    try obj.set(ctx.allocator, "__ci_cache", .{ .array = cache });
    return NativeResult.scalar(.null);
}

fn ciCacheCurrent(ctx: *NativeContext, obj: *PhpObject, inner: *PhpObject) !void {
    const valid = try ctx.vm.callMethod(inner, "valid", &.{});
    try obj.set(ctx.allocator, "__ci_valid", valid);
    if (valid.isTruthy()) {
        const cur = try ctx.vm.callMethod(inner, "current", &.{});
        const key = try ctx.vm.callMethod(inner, "key", &.{});
        try obj.set(ctx.allocator, "__ci_current", cur);
        try obj.set(ctx.allocator, "__ci_key", key);
        const flags = objGetInt(obj, "__ci_flags");
        if ((flags & 256) != 0) {
            const cache_v = obj.get("__ci_cache");
            if (cache_v == .array) {
                if (key == .string) try cache_v.array.set(ctx.allocator, .{ .string = key.string }, cur) else if (key == .int) try cache_v.array.set(ctx.allocator, .{ .int = key.int }, cur);
            }
        }
        _ = try ctx.vm.callMethod(inner, "next", &.{});
    }
}

fn ciRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    _ = try ctx.vm.callMethod(inner, "rewind", &.{});
    try ciCacheCurrent(ctx, obj, inner);
    return NativeResult.scalar(.null);
}

fn ciValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const v = obj.get("__ci_valid");
    if (v == .bool) return NativeResult.scalar(v);
    return NativeResult.scalar(.{ .bool = false });
}

fn ciCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("__ci_current"));
}

fn ciKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("__ci_key"));
}

fn ciNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.null);
    try ciCacheCurrent(ctx, obj, inner);
    return NativeResult.scalar(.null);
}

fn ciHasNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const inner = iiGetInnerObj(obj) orelse return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(try ctx.vm.callMethod(inner, "valid", &.{}));
}

fn ciToString(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    const flags = objGetInt(obj, "__ci_flags");
    const target = if ((flags & 4) != 0) obj.get("__ci_key") else if ((flags & 16) != 0) blk: {
        const inner = iiGetInnerObj(obj) orelse break :blk obj.get("__ci_current");
        break :blk try ctx.vm.callMethod(inner, "current", &.{});
    } else obj.get("__ci_current");
    if (target == .string) return NativeResult.shareString(target.string);
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(ctx.allocator);
    try target.format(&buf, ctx.allocator);
    return NativeResult.takeString(try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator)));
}

fn ciGetCache(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    return NativeResult.share(obj.get("__ci_cache"));
}

fn ciGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__ci_flags") });
}

fn ciSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__ci_flags", .{ .int = Value.toInt(args[0]) });
    return NativeResult.scalar(.null);
}

// ==========================================
// MultipleIterator
// ==========================================

fn miConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const flags: i64 = if (args.len >= 1) Value.toInt(args[0]) else 1;
    try obj.set(ctx.allocator, "__mi_flags", .{ .int = flags });
    const iters = try ctx.createArray();
    const keys = try ctx.createArray();
    try obj.set(ctx.allocator, "__mi_iters", .{ .array = iters });
    try obj.set(ctx.allocator, "__mi_keys", .{ .array = keys });
    return NativeResult.scalar(.null);
}

fn miAttach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    if (args[0] != .object and args[0] != .generator) return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array or keys_v != .array) return NativeResult.scalar(.null);
    try iters_v.array.append(ctx.allocator, args[0]);
    if (args.len >= 2 and (args[1] == .string or args[1] == .int)) {
        try keys_v.array.append(ctx.allocator, args[1]);
    } else {
        try keys_v.array.append(ctx.allocator, .null);
    }
    return NativeResult.scalar(.null);
}

fn miDetach(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array or keys_v != .array) return NativeResult.scalar(.null);
    var i: usize = 0;
    while (i < iters_v.array.entries.items.len) : (i += 1) {
        const e = iters_v.array.entries.items[i];
        if (e.value == .object and e.value.object == args[0].object) {
            _ = iters_v.array.entries.orderedRemove(i);
            if (i < keys_v.array.entries.items.len) _ = keys_v.array.entries.orderedRemove(i);
            return NativeResult.scalar(.null);
        }
    }
    return NativeResult.scalar(.null);
}

fn miContains(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    if (args.len < 1 or args[0] != .object) return NativeResult.scalar(.{ .bool = false });
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.{ .bool = false });
    for (iters_v.array.entries.items) |e| {
        if (e.value == .object and e.value.object == args[0].object) return NativeResult.scalar(.{ .bool = true });
    }
    return NativeResult.scalar(.{ .bool = false });
}

fn miCountIterators(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = iters_v.array.length() });
}

fn miCallValid(ctx: *NativeContext, v: Value) !bool {
    if (v == .object) {
        const r = try ctx.vm.callMethod(v.object, "valid", &.{});
        return r.isTruthy();
    } else if (v == .generator) {
        return v.generator.state != .completed;
    }
    return false;
}

fn miCallCurrent(ctx: *NativeContext, v: Value) !Value {
    if (v == .object) return try ctx.vm.callMethod(v.object, "current", &.{});
    if (v == .generator) return v.generator.current_value;
    return .null;
}

fn miCallKey(ctx: *NativeContext, v: Value) !Value {
    if (v == .object) return try ctx.vm.callMethod(v.object, "key", &.{});
    if (v == .generator) return v.generator.current_key;
    return .null;
}

fn miCallNext(ctx: *NativeContext, v: Value) !void {
    if (v == .object) {
        _ = try ctx.vm.callMethod(v.object, "next", &.{});
    } else if (v == .generator) {
        try ctx.vm.resumeGenerator(v.generator, .null);
    }
}

fn miCallRewind(ctx: *NativeContext, v: Value) !void {
    if (v == .object) {
        _ = try ctx.vm.callMethod(v.object, "rewind", &.{});
    } else if (v == .generator) {
        // generator auto-starts on first valid()/current() call; if not yet
        // started, kick it off so current/key are populated
        if (v.generator.state == .created) try ctx.vm.resumeGenerator(v.generator, .null);
    }
}

fn miRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.null);
    for (iters_v.array.entries.items) |e| try miCallRewind(ctx, e.value);
    return NativeResult.scalar(.null);
}

fn miValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array or iters_v.array.length() == 0) return NativeResult.scalar(.{ .bool = false });
    const flags = objGetInt(obj, "__mi_flags");
    const need_all = (flags & 1) != 0;
    var any: bool = false;
    var all: bool = true;
    for (iters_v.array.entries.items) |e| {
        if (try miCallValid(ctx, e.value)) any = true else all = false;
    }
    return NativeResult.scalar(.{ .bool = if (need_all) all else any });
}

fn miCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array) return NativeResult.scalar(.null);
    const flags = objGetInt(obj, "__mi_flags");
    const assoc = (flags & 2) != 0;
    const result = try ctx.createArray();
    var idx: i64 = 0;
    for (iters_v.array.entries.items, 0..) |e, i| {
        var v: Value = .null;
        if (try miCallValid(ctx, e.value)) v = try miCallCurrent(ctx, e.value);
        if (assoc and keys_v == .array and i < keys_v.array.entries.items.len) {
            const k = keys_v.array.entries.items[i].value;
            if (k == .string) try result.set(ctx.allocator, .{ .string = k.string }, v) else try result.append(ctx.allocator, v);
        } else {
            try result.set(ctx.allocator, .{ .int = idx }, v);
            idx += 1;
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn miKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    const keys_v = obj.get("__mi_keys");
    if (iters_v != .array) return NativeResult.scalar(.null);
    const flags = objGetInt(obj, "__mi_flags");
    const assoc = (flags & 2) != 0;
    const result = try ctx.createArray();
    var idx: i64 = 0;
    for (iters_v.array.entries.items, 0..) |e, i| {
        var v: Value = .null;
        if (try miCallValid(ctx, e.value)) v = try miCallKey(ctx, e.value);
        if (assoc and keys_v == .array and i < keys_v.array.entries.items.len) {
            const k = keys_v.array.entries.items[i].value;
            if (k == .string) try result.set(ctx.allocator, .{ .string = k.string }, v) else try result.append(ctx.allocator, v);
        } else {
            try result.set(ctx.allocator, .{ .int = idx }, v);
            idx += 1;
        }
    }
    return NativeResult.borrowed(.{ .array = result });
}

fn miNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const iters_v = obj.get("__mi_iters");
    if (iters_v != .array) return NativeResult.scalar(.null);
    for (iters_v.array.entries.items) |e| try miCallNext(ctx, e.value);
    return NativeResult.scalar(.null);
}

fn miGetFlags(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = objGetInt(obj, "__mi_flags") });
}

fn miSetFlags(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__mi_flags", .{ .int = Value.toInt(args[0]) });
    return NativeResult.scalar(.null);
}

// ==========================================
// RecursiveFilterIterator / RecursiveCallbackFilterIterator / RecursiveRegexIterator
// ==========================================

fn rfiHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const inner_v = obj.get("__fi_inner");
    if (inner_v != .object) return NativeResult.scalar(.{ .bool = false });
    return NativeResult.share(try ctx.vm.callMethod(inner_v.object, "hasChildren", &.{}));
}

fn rfiGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner_v = obj.get("__fi_inner");
    if (inner_v != .object) return NativeResult.scalar(.null);
    const child_inner = try ctx.vm.callMethod(inner_v.object, "getChildren", &.{});
    if (child_inner != .object) return NativeResult.scalar(.null);
    const new_obj = try ctx.allocator.create(PhpObject);
    new_obj.* = .{ .class_name = obj.class_name };
    try ctx.vm.objects.append(ctx.allocator, new_obj);
    ctx.vm.initObjectProperties(new_obj, obj.class_name) catch {};
    try new_obj.set(ctx.allocator, "__fi_inner", child_inner);
    return NativeResult.borrowed(.{ .object = new_obj });
}

fn rcbfGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner_v = obj.get("__fi_inner");
    if (inner_v != .object) return NativeResult.scalar(.null);
    const child_inner = try ctx.vm.callMethod(inner_v.object, "getChildren", &.{});
    if (child_inner != .object) return NativeResult.scalar(.null);
    const new_obj = try ctx.allocator.create(PhpObject);
    new_obj.* = .{ .class_name = obj.class_name };
    try ctx.vm.objects.append(ctx.allocator, new_obj);
    ctx.vm.initObjectProperties(new_obj, obj.class_name) catch {};
    try new_obj.set(ctx.allocator, "__fi_inner", child_inner);
    try new_obj.set(ctx.allocator, "__cb_fn", obj.get("__cb_fn"));
    return NativeResult.borrowed(.{ .object = new_obj });
}

fn rrxGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const inner_v = obj.get("__fi_inner");
    if (inner_v != .object) return NativeResult.scalar(.null);
    const child_inner = try ctx.vm.callMethod(inner_v.object, "getChildren", &.{});
    if (child_inner != .object) return NativeResult.scalar(.null);
    const new_obj = try ctx.allocator.create(PhpObject);
    new_obj.* = .{ .class_name = obj.class_name };
    try ctx.vm.objects.append(ctx.allocator, new_obj);
    ctx.vm.initObjectProperties(new_obj, obj.class_name) catch {};
    try new_obj.set(ctx.allocator, "__fi_inner", child_inner);
    try new_obj.set(ctx.allocator, "__rx_regex", obj.get("__rx_regex"));
    try new_obj.set(ctx.allocator, "__rx_mode", obj.get("__rx_mode"));
    try new_obj.set(ctx.allocator, "__rx_flags", obj.get("__rx_flags"));
    try new_obj.set(ctx.allocator, "__rx_preg_flags", obj.get("__rx_preg_flags"));
    return NativeResult.borrowed(.{ .object = new_obj });
}

// ==========================================
// RecursiveArrayIterator
// ==========================================

fn raiHasChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const cur = try ctx.vm.callMethod(obj, "current", &.{});
    return NativeResult.scalar(.{ .bool = cur == .array });
}

fn raiGetChildren(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const cur = try ctx.vm.callMethod(obj, "current", &.{});
    if (cur != .array) return NativeResult.scalar(.null);
    const new_obj = try ctx.allocator.create(PhpObject);
    new_obj.* = .{ .class_name = "RecursiveArrayIterator" };
    try ctx.vm.objects.append(ctx.allocator, new_obj);
    ctx.vm.initObjectProperties(new_obj, "RecursiveArrayIterator") catch {};
    _ = try ctx.vm.callMethod(new_obj, "__construct", &.{cur});
    return NativeResult.borrowed(.{ .object = new_obj });
}

// ==========================================
// RecursiveTreeIterator
// ==========================================

fn rtiConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    if (args.len < 1) return NativeResult.scalar(.null);
    // RecursiveTreeIterator default mode is SELF_FIRST; we only forward iterator + mode
    return riiConstruct(ctx, &.{ args[0], .{ .int = 1 } });
}

fn rtiCurrent(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const prefix = (try rtiGetPrefix(ctx, args)).value;
    defer if (prefix == .string) prefix.string.release();
    const entry = (try rtiGetEntry(ctx, args)).value;
    defer if (entry == .string) entry.string.release();
    const postfix = (try rtiGetPostfix(ctx, args)).value;
    defer if (postfix == .string) postfix.string.release();
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(ctx.allocator);
    if (prefix == .string) try buf.appendSlice(ctx.allocator, prefix.string.bytes());
    if (entry == .string) try buf.appendSlice(ctx.allocator, entry.string.bytes());
    if (postfix == .string) try buf.appendSlice(ctx.allocator, postfix.string.bytes());
    const s = try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator));
    _ = obj;
    return NativeResult.takeString(s);
}

fn rtiGetPrefix(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    const depth_v = try ctx.vm.callMethod(obj, "getDepth", &.{});
    const depth: i64 = if (depth_v == .int) depth_v.int else 0;
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(ctx.allocator);
    var i: i64 = 0;
    while (i < depth) : (i += 1) {
        try buf.appendSlice(ctx.allocator, "| ");
    }
    try buf.appendSlice(ctx.allocator, "|-");
    const s = try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator));
    return NativeResult.takeString(s);
}

fn rtiGetEntry(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.literal("");
    // delegate to inner current
    const inner = riiCurrentIterator(obj) orelse return NativeResult.literal("");
    const cur = try ctx.vm.callMethod(inner, "current", &.{});
    if (cur == .string) return NativeResult.share(cur);
    var buf: std.ArrayListUnmanaged(u8) = .{};
    defer buf.deinit(ctx.allocator);
    try cur.format(&buf, ctx.allocator);
    const s = try Value.String.adopt(ctx.allocator, try buf.toOwnedSlice(ctx.allocator));
    return NativeResult.takeString(s);
}

fn rtiGetPostfix(_: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    return NativeResult.literal("");
}

// ==========================================
// GlobIterator
// ==========================================

fn giConstruct(ctx: *NativeContext, args: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    if (args.len < 1 or args[0] != .string) return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__gi_pattern", args[0]);
    const result = try ctx.vm.callByName("glob", &.{args[0]});
    if (result == .array) {
        try obj.set(ctx.allocator, "__gi_results", result);
    } else {
        const empty = try ctx.allocator.create(PhpArray);
        empty.* = .{};
        try ctx.vm.arrays.append(ctx.allocator, empty);
        try obj.set(ctx.allocator, "__gi_results", .{ .array = empty });
    }
    try obj.set(ctx.allocator, "__gi_pos", .{ .int = 0 });
    return NativeResult.scalar(.null);
}

fn giRewind(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    try obj.set(ctx.allocator, "__gi_pos", .{ .int = 0 });
    const results = obj.get("__gi_results");
    if (results == .array and results.array.length() > 0) {
        const path = results.array.get(.{ .int = 0 });
        if (path == .string) {
            try obj.set(ctx.allocator, "__pathname", path);
        }
    }
    return NativeResult.scalar(.null);
}

fn giValid(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .bool = false });
    const results = obj.get("__gi_results");
    if (results != .array) return NativeResult.scalar(.{ .bool = false });
    const pos = objGetInt(obj, "__gi_pos");
    return NativeResult.scalar(.{ .bool = pos < results.array.length() });
}

fn giCurrent(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const results = obj.get("__gi_results");
    if (results != .array) return NativeResult.scalar(.null);
    const pos = objGetInt(obj, "__gi_pos");
    if (pos < 0 or pos >= results.array.length()) return NativeResult.scalar(.null);
    const path = results.array.get(.{ .int = pos });
    if (path != .string) return NativeResult.scalar(.null);
    const fi = try createFileInfoObj(ctx, path.string.bytes());
    fi.class_name = "GlobIterator";
    return NativeResult.borrowed(.{ .object = fi });
}

fn giKey(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const results = obj.get("__gi_results");
    if (results != .array) return NativeResult.scalar(.{ .int = 0 });
    const pos = objGetInt(obj, "__gi_pos");
    if (pos < 0 or pos >= results.array.length()) return NativeResult.scalar(.{ .int = 0 });
    const path = results.array.get(.{ .int = pos });
    if (path == .string) return NativeResult.share(path);
    return NativeResult.scalar(.{ .int = pos });
}

fn giNext(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.null);
    const pos = objGetInt(obj, "__gi_pos");
    try obj.set(ctx.allocator, "__gi_pos", .{ .int = pos + 1 });
    const results = obj.get("__gi_results");
    if (results == .array and pos + 1 < results.array.length()) {
        const path = results.array.get(.{ .int = pos + 1 });
        if (path == .string) {
            try obj.set(ctx.allocator, "__pathname", path);
        }
    }
    return NativeResult.scalar(.null);
}

fn giCount(ctx: *NativeContext, _: []const Value) RuntimeError!NativeResult {
    const obj = getThis(ctx) orelse return NativeResult.scalar(.{ .int = 0 });
    const results = obj.get("__gi_results");
    if (results != .array) return NativeResult.scalar(.{ .int = 0 });
    return NativeResult.scalar(.{ .int = results.array.length() });
}
