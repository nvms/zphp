const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const pcre2 = struct {
    const Code = opaque {};
    const MatchData = opaque {};

    const CASELESS: u32 = 0x00000008;
    const MULTILINE: u32 = 0x00000400;
    const DOTALL: u32 = 0x00000020;
    const EXTENDED: u32 = 0x00000080;
    const UTF: u32 = 0x00080000;
    const ANCHORED: u32 = 0x80000000;

    const SUBSTITUTE_GLOBAL: u32 = 0x00000100;
    const SUBSTITUTE_OVERFLOW_LENGTH: u32 = 0x00001000;

    const INFO_CAPTURECOUNT: u32 = 4;
    const INFO_NAMECOUNT: u32 = 17;
    const INFO_NAMEENTRYSIZE: u32 = 18;
    const INFO_NAMETABLE: u32 = 19;
    const ERROR_NOMEMORY: c_int = -48;
    const UNSET: usize = std.math.maxInt(usize);

    extern "pcre2-8" fn pcre2_compile_8(
        pattern: [*]const u8,
        length: usize,
        options: u32,
        errorcode: *c_int,
        erroroffset: *usize,
        ccontext: ?*anyopaque,
    ) callconv(.c) ?*Code;

    extern "pcre2-8" fn pcre2_code_free_8(code: ?*Code) callconv(.c) void;

    extern "pcre2-8" fn pcre2_match_data_create_from_pattern_8(
        code: *const Code,
        gcontext: ?*anyopaque,
    ) callconv(.c) ?*MatchData;

    extern "pcre2-8" fn pcre2_match_data_free_8(match_data: ?*MatchData) callconv(.c) void;

    extern "pcre2-8" fn pcre2_match_8(
        code: *const Code,
        subject: [*]const u8,
        length: usize,
        startoffset: usize,
        options: u32,
        match_data: *MatchData,
        mcontext: ?*anyopaque,
    ) callconv(.c) c_int;

    extern "pcre2-8" fn pcre2_get_ovector_pointer_8(
        match_data: *MatchData,
    ) callconv(.c) [*]usize;

    extern "pcre2-8" fn pcre2_pattern_info_8(
        code: *const Code,
        what: u32,
        where: *anyopaque,
    ) callconv(.c) c_int;

    extern "pcre2-8" fn pcre2_get_mark_8(
        match_data: *MatchData,
    ) callconv(.c) ?[*:0]const u8;

    extern "pcre2-8" fn pcre2_substitute_8(
        code: *const Code,
        subject: [*]const u8,
        length: usize,
        startoffset: usize,
        options: u32,
        match_data: ?*MatchData,
        mcontext: ?*anyopaque,
        replacement: [*]const u8,
        rlength: usize,
        outputbuffer: ?[*]u8,
        outlengthptr: *usize,
    ) callconv(.c) c_int;
};

pub const entries = .{
    .{ "preg_match", preg_match },
    .{ "preg_match_all", preg_match_all },
    .{ "preg_replace", preg_replace },
    .{ "preg_replace_callback", preg_replace_callback },
    .{ "preg_replace_callback_array", preg_replace_callback_array },
    .{ "preg_split", preg_split },
    .{ "preg_quote", preg_quote },
    .{ "preg_grep", preg_grep },
    .{ "preg_last_error", preg_last_error },
    .{ "preg_last_error_msg", preg_last_error_msg },
    .{ "mb_split", mb_split },
    .{ "mb_ereg_match", mb_ereg_match },
};

const PatternInfo = struct {
    pattern: []const u8,
    flags: u32,
};

fn parsePattern(raw: []const u8) ?PatternInfo {
    if (raw.len < 2) return null;
    const delim = raw[0];
    if (delim == '\\' or std.ascii.isAlphanumeric(delim)) return null;

    const close_delim: u8 = switch (delim) {
        '(' => ')',
        '{' => '}',
        '[' => ']',
        '<' => '>',
        else => delim,
    };

    var end = raw.len - 1;
    while (end > 0 and raw[end] != close_delim) end -= 1;
    if (end == 0) return null;

    const pattern = raw[1..end];
    const modifiers = raw[end + 1 ..];

    var flags: u32 = 0;
    for (modifiers) |m| {
        switch (m) {
            'i' => flags |= pcre2.CASELESS,
            'm' => flags |= pcre2.MULTILINE,
            's' => flags |= pcre2.DOTALL,
            'x' => flags |= pcre2.EXTENDED,
            'u' => flags |= pcre2.UTF,
            'A' => flags |= pcre2.ANCHORED,
            else => {},
        }
    }
    return .{ .pattern = pattern, .flags = flags };
}

fn compilePattern(pattern: []const u8, flags: u32) ?*pcre2.Code {
    var err_code: c_int = 0;
    var err_offset: usize = 0;
    return pcre2.pcre2_compile_8(
        pattern.ptr,
        pattern.len,
        flags,
        &err_code,
        &err_offset,
        null,
    );
}

fn preg_match(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = 0 };
    const info = parsePattern(args[0].string) orelse return Value{ .int = 0 };
    const subject = args[1].string;

    const code = compilePattern(info.pattern, info.flags) orelse return Value{ .int = 0 };
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value{ .int = 0 };
    defer pcre2.pcre2_match_data_free_8(match_data);

    const flags: u32 = if (args.len >= 4) @intCast(@max(0, Value.toInt(args[3]))) else 0;
    const offset_capture = (flags & 256) != 0;
    const unmatched_as_null = (flags & 512) != 0;
    const offset: usize = if (args.len >= 5 and args[4] == .int and args[4].int >= 0) @intCast(args[4].int) else 0;
    const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
    if (rc < 0) return .{ .int = 0 };

    if (args.len >= 3) {
        const matches_arr = if (args[2] == .array) args[2].array else try ctx.createArray();
        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const count: usize = @intCast(rc);

        matches_arr.entries.items.len = 0;
        matches_arr.next_int_key = 0;

        for (0..count) |i| {
            const start = ovector[i * 2];
            const end = ovector[i * 2 + 1];
            if (start == pcre2.UNSET or end == pcre2.UNSET) {
                const val: Value = if (unmatched_as_null) .null else if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = "" };
                try matches_arr.append(ctx.allocator, val);
            } else {
                const str = try ctx.createString(subject[start..end]);
                const val = if (offset_capture) try makeOffsetPair(ctx, str, @intCast(start)) else Value{ .string = str };
                try matches_arr.append(ctx.allocator, val);
            }
        }
        try addNamedGroupsInterleaved(ctx, matches_arr, code, ovector, subject, count, offset_capture, unmatched_as_null);
        if (pcre2.pcre2_get_mark_8(match_data)) |mark_ptr| {
            const mark = std.mem.sliceTo(mark_ptr, 0);
            if (mark.len > 0) {
                try matches_arr.set(ctx.allocator, .{ .string = try ctx.createString("MARK") }, .{ .string = try ctx.createString(mark) });
            }
        }
        if (args[2] != .array) {
            ctx.setCallerVar(2, args.len, .{ .array = matches_arr });
        }
    }

    return .{ .int = 1 };
}

fn addNamedGroupsInterleaved(ctx: *NativeContext, arr: *PhpArray, code: *pcre2.Code, ovector: [*]usize, subject: []const u8, count: usize, offset_capture: bool, unmatched_as_null: bool) !void {
    var name_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMECOUNT, @ptrCast(&name_count));
    if (name_count == 0) return;
    var name_entry_size: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&name_entry_size));
    if (name_entry_size == 0) return;

    var name_table: [*]const u8 = undefined;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMETABLE, @ptrCast(&name_table));

    // collect named groups sorted by group_num so we can insert in order
    const NamedGroup = struct { group_num: usize, name: []const u8 };
    var groups: [64]NamedGroup = undefined;
    var group_len: usize = 0;
    for (0..name_count) |i| {
        const entry = name_table + i * name_entry_size;
        const group_num = (@as(usize, entry[0]) << 8) | @as(usize, entry[1]);
        const name_end = std.mem.indexOfScalar(u8, entry[2..name_entry_size], 0) orelse (name_entry_size - 2);
        if (group_len < groups.len) {
            groups[group_len] = .{ .group_num = group_num, .name = entry[2 .. 2 + name_end] };
            group_len += 1;
        }
    }
    // sort by group_num descending so we insert from the back
    std.mem.sort(NamedGroup, groups[0..group_len], {}, struct {
        fn f(_: void, a: NamedGroup, b: NamedGroup) bool {
            return a.group_num > b.group_num;
        }
    }.f);

    for (groups[0..group_len]) |ng| {
        if (ng.group_num < count) {
            const start = ovector[ng.group_num * 2];
            const end = ovector[ng.group_num * 2 + 1];
            const val: Value = if (start == pcre2.UNSET or end == pcre2.UNSET) blk: {
                if (unmatched_as_null) break :blk .null;
                break :blk if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = "" };
            } else blk: {
                const s = try ctx.createString(subject[start..end]);
                break :blk if (offset_capture) try makeOffsetPair(ctx, s, @intCast(start)) else Value{ .string = s };
            };
            // PHP places the named key directly before its numeric counterpart
            const insert_pos = ng.group_num;
            const named_entry = PhpArray.Entry{ .key = .{ .string = try ctx.createString(ng.name) }, .value = val };
            if (insert_pos < arr.entries.items.len) {
                try arr.entries.insert(ctx.allocator, insert_pos, named_entry);
            } else {
                try arr.entries.append(ctx.allocator, named_entry);
            }
            try arr.rebuildStringIndex(ctx.allocator);
        }
    }
}

fn addNamedGroups(ctx: *NativeContext, arr: *PhpArray, code: *pcre2.Code, ovector: [*]usize, subject: []const u8, count: usize) !void {
    var name_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMECOUNT, @ptrCast(&name_count));
    if (name_count == 0) return;
    var name_entry_size: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&name_entry_size));
    if (name_entry_size == 0) return;

    var name_table: [*]const u8 = undefined;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMETABLE, @ptrCast(&name_table));

    for (0..name_count) |i| {
        const entry = name_table + i * name_entry_size;
        const group_num = (@as(usize, entry[0]) << 8) | @as(usize, entry[1]);
        const name_end = std.mem.indexOfScalar(u8, entry[2..name_entry_size], 0) orelse (name_entry_size - 2);
        const name = entry[2 .. 2 + name_end];
        if (group_num < count) {
            const start = ovector[group_num * 2];
            const end = ovector[group_num * 2 + 1];
            const val: Value = if (start == pcre2.UNSET or end == pcre2.UNSET)
                .{ .string = "" }
            else
                .{ .string = try ctx.createString(subject[start..end]) };
            try arr.set(ctx.allocator, .{ .string = try ctx.createString(name) }, val);
        }
    }
}

fn preg_match_all(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = 0 };
    const info = parsePattern(args[0].string) orelse return Value{ .int = 0 };
    const subject = args[1].string;

    const flags: u32 = if (args.len >= 4) @intCast(@max(0, Value.toInt(args[3]))) else 0;
    const set_order = (flags & 2) != 0; // PREG_SET_ORDER
    const offset_capture = (flags & 256) != 0; // PREG_OFFSET_CAPTURE

    const code = compilePattern(info.pattern, info.flags) orelse return Value{ .int = 0 };
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value{ .int = 0 };
    defer pcre2.pcre2_match_data_free_8(match_data);

    var capture_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_CAPTURECOUNT, @ptrCast(&capture_count));
    const group_count: usize = capture_count + 1;

    const out = if (args.len >= 3 and args[2] == .array) args[2].array else try ctx.createArray();
    out.entries.items.len = 0;
    out.next_int_key = 0;

    var group_arrays: ?std.ArrayListUnmanaged(*PhpArray) = null;
    if (!set_order) {
        var ga = std.ArrayListUnmanaged(*PhpArray){};
        for (0..group_count) |_| {
            try ga.append(ctx.allocator, try ctx.createArray());
        }
        group_arrays = ga;
    }
    defer if (group_arrays) |*ga| ga.deinit(ctx.allocator);

    var total_matches: i64 = 0;
    var offset: usize = 0;

    while (offset <= subject.len) {
        const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
        if (rc < 0) break;

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const count: usize = @intCast(rc);

        if (set_order) {
            const match_arr = try ctx.createArray();
            // find last matched group (PHP omits trailing unmatched groups in SET_ORDER)
            var last_matched: usize = 0;
            for (0..group_count) |i| {
                if (i < count) {
                    const s = ovector[i * 2];
                    const e = ovector[i * 2 + 1];
                    if (s != pcre2.UNSET and e != pcre2.UNSET) {
                        last_matched = i;
                    }
                }
            }
            for (0..last_matched + 1) |i| {
                const val = try matchGroupValue(ctx, subject, ovector, count, i, offset_capture);
                try match_arr.append(ctx.allocator, val);
            }
            try addNamedGroupsToMatch(ctx, match_arr, code, ovector, subject, count, offset_capture);
            try out.append(ctx.allocator, .{ .array = match_arr });
        } else {
            for (0..group_count) |i| {
                const val = try matchGroupValue(ctx, subject, ovector, count, i, offset_capture);
                try group_arrays.?.items[i].append(ctx.allocator, val);
            }
        }

        total_matches += 1;
        const match_end = ovector[1];
        if (match_end == offset) {
            offset += 1;
        } else {
            offset = match_end;
        }
    }

    if (!set_order) {
        // add named group arrays interleaved with their numeric index
        var name_count_val: u32 = 0;
        _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMECOUNT, @ptrCast(&name_count_val));
        var name_entry_size_val: u32 = 0;
        _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&name_entry_size_val));

        const NamedGroup = struct { group_num: usize, name: []const u8 };
        var named_groups: [64]NamedGroup = undefined;
        var named_len: usize = 0;
        if (name_count_val > 0 and name_entry_size_val > 0) {
            var name_table_ptr: [*]const u8 = undefined;
            _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMETABLE, @ptrCast(&name_table_ptr));
            for (0..name_count_val) |ni| {
                const entry = name_table_ptr + ni * name_entry_size_val;
                const gn = (@as(usize, entry[0]) << 8) | @as(usize, entry[1]);
                const ne = std.mem.indexOfScalar(u8, entry[2..name_entry_size_val], 0) orelse (name_entry_size_val - 2);
                if (named_len < named_groups.len) {
                    named_groups[named_len] = .{ .group_num = gn, .name = entry[2 .. 2 + ne] };
                    named_len += 1;
                }
            }
            // sort by group_num descending for insertion
            std.mem.sort(NamedGroup, named_groups[0..named_len], {}, struct {
                fn f(_: void, a: NamedGroup, b: NamedGroup) bool {
                    return a.group_num > b.group_num;
                }
            }.f);
        }

        for (group_arrays.?.items) |arr| {
            try out.append(ctx.allocator, .{ .array = arr });
        }

        // PHP places the named key directly before its numeric counterpart
        for (named_groups[0..named_len]) |ng| {
            if (ng.group_num < group_arrays.?.items.len) {
                const insert_pos = ng.group_num;
                const named_entry = PhpArray.Entry{
                    .key = .{ .string = try ctx.createString(ng.name) },
                    .value = .{ .array = group_arrays.?.items[ng.group_num] },
                };
                if (insert_pos < out.entries.items.len) {
                    try out.entries.insert(ctx.allocator, insert_pos, named_entry);
                } else {
                    try out.entries.append(ctx.allocator, named_entry);
                }
            }
        }
        try out.rebuildStringIndex(ctx.allocator);
    }

    if (args.len >= 3 and args[2] != .array) {
        ctx.setCallerVar(2, args.len, .{ .array = out });
    }

    return .{ .int = total_matches };
}

fn matchGroupValue(ctx: *NativeContext, subject: []const u8, ovector: [*]usize, count: usize, i: usize, offset_capture: bool) RuntimeError!Value {
    if (i < count) {
        const start = ovector[i * 2];
        const end = ovector[i * 2 + 1];
        if (start == pcre2.UNSET or end == pcre2.UNSET) {
            return if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = "" };
        }
        const str = try ctx.createString(subject[start..end]);
        return if (offset_capture) try makeOffsetPair(ctx, str, @intCast(start)) else Value{ .string = str };
    }
    return if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = "" };
}

fn makeOffsetPair(ctx: *NativeContext, str: []const u8, offset: i64) RuntimeError!Value {
    const pair = try ctx.createArray();
    try pair.append(ctx.allocator, .{ .string = str });
    try pair.append(ctx.allocator, .{ .int = offset });
    return Value{ .array = pair };
}

fn addNamedGroupsToMatch(ctx: *NativeContext, arr: *PhpArray, code: *pcre2.Code, ovector: [*]usize, subject: []const u8, count: usize, offset_capture: bool) !void {
    var name_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMECOUNT, @ptrCast(&name_count));
    if (name_count == 0) return;
    var name_entry_size: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMEENTRYSIZE, @ptrCast(&name_entry_size));
    if (name_entry_size == 0) return;

    var name_table: [*]const u8 = undefined;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_NAMETABLE, @ptrCast(&name_table));

    const NamedGroup = struct { group_num: usize, name: []const u8 };
    var groups: [64]NamedGroup = undefined;
    var group_len: usize = 0;
    for (0..name_count) |i| {
        const entry = name_table + i * name_entry_size;
        const group_num = (@as(usize, entry[0]) << 8) | @as(usize, entry[1]);
        const name_end = std.mem.indexOfScalar(u8, entry[2..name_entry_size], 0) orelse (name_entry_size - 2);
        if (group_len < groups.len) {
            groups[group_len] = .{ .group_num = group_num, .name = entry[2 .. 2 + name_end] };
            group_len += 1;
        }
    }
    std.mem.sort(NamedGroup, groups[0..group_len], {}, struct {
        fn f(_: void, a: NamedGroup, b: NamedGroup) bool {
            return a.group_num > b.group_num;
        }
    }.f);

    for (groups[0..group_len]) |ng| {
        if (ng.group_num >= count) continue;
        const start = ovector[ng.group_num * 2];
        const end = ovector[ng.group_num * 2 + 1];
        const val: Value = if (start == pcre2.UNSET or end == pcre2.UNSET) blk: {
            break :blk if (offset_capture) try makeOffsetPair(ctx, "", -1) else Value{ .string = "" };
        } else blk: {
            const s = try ctx.createString(subject[start..end]);
            break :blk if (offset_capture) try makeOffsetPair(ctx, s, @intCast(start)) else Value{ .string = s };
        };
        const insert_pos = ng.group_num;
        const named_entry = PhpArray.Entry{ .key = .{ .string = try ctx.createString(ng.name) }, .value = val };
        if (insert_pos < arr.entries.items.len) {
            try arr.entries.insert(ctx.allocator, insert_pos, named_entry);
        } else {
            try arr.entries.append(ctx.allocator, named_entry);
        }
    }
    try arr.rebuildStringIndex(ctx.allocator);
}

fn translateReplacement(allocator: std.mem.Allocator, src: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    defer out.deinit(allocator);
    var i: usize = 0;
    while (i < src.len) {
        const c = src[i];
        if (c == '\\' and i + 1 < src.len) {
            const n = src[i + 1];
            if (n >= '0' and n <= '9') {
                try out.append(allocator, '$');
                try out.append(allocator, n);
                i += 2;
                continue;
            }
            if (n == '\\') {
                try out.append(allocator, '\\');
                i += 2;
                continue;
            }
            if (n == '$') {
                try out.append(allocator, '\\');
                try out.append(allocator, '$');
                i += 2;
                continue;
            }
            try out.append(allocator, c);
            i += 1;
            continue;
        }
        try out.append(allocator, c);
        i += 1;
    }
    return out.toOwnedSlice(allocator);
}

fn preg_replace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string or args[2] != .string) return if (args.len >= 3) args[2] else Value.null;
    const info = parsePattern(args[0].string) orelse return args[2];
    const replacement = if (args[1] == .string) args[1].string else return args[2];
    const subject = args[2].string;
    const limit: i64 = if (args.len >= 4 and args[3] != .null) Value.toInt(args[3]) else -1;

    const code = compilePattern(info.pattern, info.flags) orelse return args[2];
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return args[2];
    defer pcre2.pcre2_match_data_free_8(match_data);

    if (limit > 0) {
        return pregReplaceLimited(ctx, code, match_data, subject, replacement, @intCast(limit), args);
    }

    const xrep = try translateReplacement(ctx.allocator, replacement);
    defer ctx.allocator.free(xrep);

    const sub_opts: u32 = pcre2.SUBSTITUTE_OVERFLOW_LENGTH | pcre2.SUBSTITUTE_GLOBAL;

    var out_len: usize = 0;
    var rc = pcre2.pcre2_substitute_8(
        code,
        subject.ptr,
        subject.len,
        0,
        sub_opts,
        match_data,
        null,
        xrep.ptr,
        xrep.len,
        null,
        &out_len,
    );

    if (rc >= 0) {
        ctx.setCallerVar(4, args.len, .{ .int = @intCast(rc) });
        return args[2];
    }
    if (rc != pcre2.ERROR_NOMEMORY) {
        ctx.setCallerVar(4, args.len, .{ .int = 0 });
        return args[2];
    }

    const buf = try ctx.allocator.alloc(u8, out_len);
    rc = pcre2.pcre2_substitute_8(
        code,
        subject.ptr,
        subject.len,
        0,
        sub_opts,
        match_data,
        null,
        xrep.ptr,
        xrep.len,
        buf.ptr,
        &out_len,
    );

    if (rc < 0) {
        ctx.allocator.free(buf);
        ctx.setCallerVar(4, args.len, .{ .int = 0 });
        return args[2];
    }

    ctx.setCallerVar(4, args.len, .{ .int = @intCast(rc) });
    const result = buf[0..out_len];
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = result };
}

fn pregReplaceLimited(ctx: *NativeContext, code: *pcre2.Code, match_data: *pcre2.MatchData, subject: []const u8, replacement: []const u8, limit: usize, args: []const Value) RuntimeError!Value {
    var parts = std.ArrayListUnmanaged(u8){};
    defer parts.deinit(ctx.allocator);
    var offset: usize = 0;
    var count: usize = 0;

    while (offset <= subject.len and count < limit) {
        const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
        if (rc < 0) break;

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const ms = ovector[0];
        const me = ovector[1];

        try parts.appendSlice(ctx.allocator, subject[offset..ms]);

        // handle backreferences in replacement
        var ri: usize = 0;
        while (ri < replacement.len) {
            if (replacement[ri] == '$' and ri + 1 < replacement.len and replacement[ri + 1] >= '0' and replacement[ri + 1] <= '9') {
                const group = replacement[ri + 1] - '0';
                ri += 2;
                if (group < @as(u8, @intCast(rc))) {
                    const gs = ovector[2 * @as(usize, group)];
                    const ge = ovector[2 * @as(usize, group) + 1];
                    if (gs <= subject.len and ge <= subject.len) {
                        try parts.appendSlice(ctx.allocator, subject[gs..ge]);
                    }
                }
            } else if (replacement[ri] == '\\' and ri + 1 < replacement.len and replacement[ri + 1] >= '0' and replacement[ri + 1] <= '9') {
                const group = replacement[ri + 1] - '0';
                ri += 2;
                if (group < @as(u8, @intCast(rc))) {
                    const gs = ovector[2 * @as(usize, group)];
                    const ge = ovector[2 * @as(usize, group) + 1];
                    if (gs <= subject.len and ge <= subject.len) {
                        try parts.appendSlice(ctx.allocator, subject[gs..ge]);
                    }
                }
            } else {
                try parts.append(ctx.allocator, replacement[ri]);
                ri += 1;
            }
        }

        count += 1;
        if (me == offset) {
            if (offset < subject.len) {
                try parts.append(ctx.allocator, subject[offset]);
            }
            offset += 1;
        } else {
            offset = me;
        }
    }

    if (offset <= subject.len) {
        try parts.appendSlice(ctx.allocator, subject[offset..]);
    }

    const buf = try ctx.allocator.alloc(u8, parts.items.len);
    @memcpy(buf, parts.items);
    try ctx.strings.append(ctx.allocator, buf);
    ctx.setCallerVar(4, args.len, .{ .int = @intCast(count) });
    return .{ .string = buf };
}

fn preg_replace_callback(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string or args[2] != .string) return if (args.len >= 3) args[2] else Value.null;
    const info = parsePattern(args[0].string) orelse return args[2];
    const callback = args[1];
    const subject = args[2].string;

    const code = compilePattern(info.pattern, info.flags) orelse return args[2];
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return args[2];
    defer pcre2.pcre2_match_data_free_8(match_data);

    var capture_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_CAPTURECOUNT, @ptrCast(&capture_count));
    const group_count: usize = capture_count + 1;

    var result = std.ArrayListUnmanaged(u8){};
    var offset: usize = 0;

    while (offset <= subject.len) {
        const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
        if (rc < 0) break;

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovector[0];
        const match_end = ovector[1];

        try result.appendSlice(ctx.allocator, subject[offset..match_start]);

        const matches_arr = try ctx.allocator.create(PhpArray);
        matches_arr.* = .{};
        try ctx.arrays.append(ctx.allocator, matches_arr);
        for (0..group_count) |gi| {
            const gs = ovector[gi * 2];
            const ge = ovector[gi * 2 + 1];
            if (gs == pcre2.UNSET or ge == pcre2.UNSET or gs > subject.len or ge > subject.len) {
                try matches_arr.append(ctx.allocator, .{ .string = "" });
            } else {
                try matches_arr.append(ctx.allocator, .{ .string = subject[gs..ge] });
            }
        }

        const cb_result = try ctx.invokeCallable(callback, &.{.{ .array = matches_arr }});
        if (cb_result == .string) {
            try result.appendSlice(ctx.allocator, cb_result.string);
        } else {
            var buf = std.ArrayListUnmanaged(u8){};
            try cb_result.format(&buf, ctx.allocator);
            const s = try buf.toOwnedSlice(ctx.allocator);
            try ctx.strings.append(ctx.allocator, s);
            try result.appendSlice(ctx.allocator, s);
        }

        if (match_end == offset) {
            if (offset < subject.len) {
                try result.append(ctx.allocator, subject[offset]);
            }
            offset += 1;
        } else {
            offset = match_end;
        }
    }

    if (offset < subject.len) {
        try result.appendSlice(ctx.allocator, subject[offset..]);
    }

    const s = try result.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, s);
    return .{ .string = s };
}

fn preg_replace_callback_array(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .array) return if (args.len >= 2) args[1] else Value.null;
    const map = args[0].array;
    var current: Value = args[1];
    if (current != .string) return current;

    for (map.entries.items) |entry| {
        if (entry.key != .string) continue;
        const sub_args = [_]Value{
            .{ .string = entry.key.string },
            entry.value,
            current,
        };
        const r = try preg_replace_callback(ctx, &sub_args);
        if (r == .string) current = r;
    }
    return current;
}

fn preg_split(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const info = parsePattern(args[0].string) orelse return Value.null;
    const subject = args[1].string;
    const limit: i64 = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else -1;
    const flags: i64 = if (args.len >= 4) Value.toInt(args[3]) else 0;
    const delim_capture = (flags & 2) != 0;
    const no_empty = (flags & 1) != 0;
    const offset_capture = (flags & 4) != 0;

    const code = compilePattern(info.pattern, info.flags) orelse return Value.null;
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value.null;
    defer pcre2.pcre2_match_data_free_8(match_data);

    var result = try ctx.createArray();
    var offset: usize = 0;
    var splits: i64 = 1;

    while (offset <= subject.len) {
        if (limit > 0 and splits >= limit) break;

        const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
        if (rc < 0) break;

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovector[0];
        const match_end = ovector[1];

        const piece = try ctx.createString(subject[offset..match_start]);
        if (!no_empty or piece.len > 0) {
            if (offset_capture) {
                var pair = try ctx.createArray();
                try pair.append(ctx.allocator, .{ .string = piece });
                try pair.append(ctx.allocator, .{ .int = @intCast(offset) });
                try result.append(ctx.allocator, .{ .array = pair });
            } else {
                try result.append(ctx.allocator, .{ .string = piece });
            }
        }
        splits += 1;

        if (delim_capture and rc > 1) {
            var i: usize = 1;
            while (i < @as(usize, @intCast(rc))) : (i += 1) {
                const gs = ovector[2 * i];
                const ge = ovector[2 * i + 1];
                if (gs <= subject.len and ge <= subject.len) {
                    const cap = try ctx.createString(subject[gs..ge]);
                    if (!no_empty or cap.len > 0) {
                        if (offset_capture) {
                            var pair = try ctx.createArray();
                            try pair.append(ctx.allocator, .{ .string = cap });
                            try pair.append(ctx.allocator, .{ .int = @intCast(gs) });
                            try result.append(ctx.allocator, .{ .array = pair });
                        } else {
                            try result.append(ctx.allocator, .{ .string = cap });
                        }
                    }
                } else if (!no_empty) {
                    if (offset_capture) {
                        var pair = try ctx.createArray();
                        try pair.append(ctx.allocator, .{ .string = "" });
                        try pair.append(ctx.allocator, .{ .int = 0 });
                        try result.append(ctx.allocator, .{ .array = pair });
                    } else {
                        try result.append(ctx.allocator, .{ .string = "" });
                    }
                }
            }
        }

        if (match_end == offset) {
            if (offset < subject.len) {
                const single = try ctx.createString(subject[offset .. offset + 1]);
                if (!no_empty or single.len > 0) {
                    if (offset_capture) {
                        var pair = try ctx.createArray();
                        try pair.append(ctx.allocator, .{ .string = single });
                        try pair.append(ctx.allocator, .{ .int = @intCast(offset) });
                        try result.append(ctx.allocator, .{ .array = pair });
                    } else {
                        try result.append(ctx.allocator, .{ .string = single });
                    }
                }
            }
            offset += 1;
        } else {
            offset = match_end;
        }
    }

    if (offset <= subject.len) {
        const tail = try ctx.createString(subject[offset..]);
        if (!no_empty or tail.len > 0) {
            if (offset_capture) {
                var pair = try ctx.createArray();
                try pair.append(ctx.allocator, .{ .string = tail });
                try pair.append(ctx.allocator, .{ .int = @intCast(offset) });
                try result.append(ctx.allocator, .{ .array = pair });
            } else {
                try result.append(ctx.allocator, .{ .string = tail });
            }
        }
    }

    return .{ .array = result };
}

fn preg_quote(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len == 0 or args[0] != .string) return .{ .string = "" };
    const input = args[0].string;
    const delimiter: ?u8 = if (args.len >= 2 and args[1] == .string and args[1].string.len > 0) args[1].string[0] else null;

    // pcre special chars: . \ + * ? [ ^ ] $ ( ) { } = ! < > | : - #
    const specials = ".\\+*?[^]$(){}=!<>|:-#";

    var buf = std.ArrayListUnmanaged(u8){};
    for (input) |c| {
        if (delimiter != null and c == delimiter.?) {
            try buf.append(ctx.allocator, '\\');
        } else if (std.mem.indexOfScalar(u8, specials, c) != null) {
            try buf.append(ctx.allocator, '\\');
        }
        try buf.append(ctx.allocator, c);
    }
    const result = try buf.toOwnedSlice(ctx.allocator);
    try ctx.strings.append(ctx.allocator, result);
    return .{ .string = result };
}

fn preg_grep(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .array) return .null;
    const info = parsePattern(args[0].string) orelse return Value.null;
    const input = args[1].array;
    const invert = args.len >= 3 and Value.toInt(args[2]) == 1;

    const code = compilePattern(info.pattern, info.flags) orelse return Value.null;
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value.null;
    defer pcre2.pcre2_match_data_free_8(match_data);

    var result = try ctx.createArray();
    for (input.entries.items) |entry| {
        const str = if (entry.value == .string) entry.value.string else continue;
        const rc = pcre2.pcre2_match_8(code, str.ptr, str.len, 0, 0, match_data, null);
        const matched = rc >= 0;
        if (matched != invert) {
            try result.set(ctx.allocator, entry.key, entry.value);
        }
    }
    return .{ .array = result };
}

fn preg_last_error(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .int = 0 };
}

fn preg_last_error_msg(_: *NativeContext, _: []const Value) RuntimeError!Value {
    return .{ .string = "No error" };
}

fn mb_split(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const pattern = args[0].string;
    const subject = args[1].string;
    const limit: i64 = if (args.len >= 3 and args[2] != .null) Value.toInt(args[2]) else -1;

    const code = compilePattern(pattern, pcre2.UTF) orelse return Value.null;
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value.null;
    defer pcre2.pcre2_match_data_free_8(match_data);

    var result = try ctx.createArray();
    var offset: usize = 0;
    var splits: i64 = 1;

    while (offset <= subject.len) {
        if (limit > 0 and splits >= limit) break;

        const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
        if (rc < 0) break;

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovector[0];
        const match_end = ovector[1];

        try result.append(ctx.allocator, .{ .string = try ctx.createString(subject[offset..match_start]) });
        splits += 1;

        if (match_end == offset) {
            if (offset < subject.len) {
                try result.append(ctx.allocator, .{ .string = try ctx.createString(subject[offset .. offset + 1]) });
            }
            offset += 1;
        } else {
            offset = match_end;
        }
    }

    if (offset <= subject.len) {
        try result.append(ctx.allocator, .{ .string = try ctx.createString(subject[offset..]) });
    }

    return .{ .array = result };
}

fn mb_ereg_match(_: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .bool = false };
    const pattern = args[0].string;
    const subject = args[1].string;

    const code = compilePattern(pattern, pcre2.UTF | pcre2.ANCHORED) orelse return .{ .bool = false };
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return .{ .bool = false };
    defer pcre2.pcre2_match_data_free_8(match_data);

    const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, 0, 0, match_data, null);
    return .{ .bool = rc >= 0 };
}
