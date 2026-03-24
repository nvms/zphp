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
    .{ "preg_split", preg_split },
};

const PatternInfo = struct {
    pattern: []const u8,
    flags: u32,
};

fn parsePattern(raw: []const u8) ?PatternInfo {
    if (raw.len < 2) return null;
    const delim = raw[0];
    if (delim == '\\' or std.ascii.isAlphanumeric(delim)) return null;

    var end = raw.len - 1;
    while (end > 0 and raw[end] != delim) end -= 1;
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

    const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, 0, 0, match_data, null);
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
                try matches_arr.append(ctx.allocator, .{ .string = "" });
            } else {
                try matches_arr.append(ctx.allocator, .{ .string = try ctx.createString(subject[start..end]) });
            }
        }
        try addNamedGroups(ctx, matches_arr, code, ovector, subject, count);
        if (args[2] != .array) {
            ctx.setCallerVar(2, args.len, .{ .array = matches_arr });
        }
    }

    return .{ .int = 1 };
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

    const code = compilePattern(info.pattern, info.flags) orelse return Value{ .int = 0 };
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value{ .int = 0 };
    defer pcre2.pcre2_match_data_free_8(match_data);

    var capture_count: u32 = 0;
    _ = pcre2.pcre2_pattern_info_8(code, pcre2.INFO_CAPTURECOUNT, @ptrCast(&capture_count));
    const group_count: usize = capture_count + 1;

    var group_arrays = std.ArrayListUnmanaged(*PhpArray){};
    for (0..group_count) |_| {
        const arr = try ctx.createArray();
        try group_arrays.append(ctx.allocator, arr);
    }
    defer group_arrays.deinit(ctx.allocator);

    var total_matches: i64 = 0;
    var offset: usize = 0;

    while (offset <= subject.len) {
        const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
        if (rc < 0) break;

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const count: usize = @intCast(rc);

        for (0..group_count) |i| {
            if (i < count) {
                const start = ovector[i * 2];
                const end = ovector[i * 2 + 1];
                if (start == pcre2.UNSET or end == pcre2.UNSET) {
                    try group_arrays.items[i].append(ctx.allocator, .{ .string = "" });
                } else {
                    try group_arrays.items[i].append(ctx.allocator, .{ .string = try ctx.createString(subject[start..end]) });
                }
            } else {
                try group_arrays.items[i].append(ctx.allocator, .{ .string = "" });
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

    if (args.len >= 3) {
        const out = if (args[2] == .array) args[2].array else try ctx.createArray();
        out.entries.items.len = 0;
        out.next_int_key = 0;
        for (group_arrays.items) |arr| {
            try out.append(ctx.allocator, .{ .array = arr });
        }
        if (args[2] != .array) {
            ctx.setCallerVar(2, args.len, .{ .array = out });
        }
    }

    return .{ .int = total_matches };
}

fn preg_replace(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 3 or args[0] != .string or args[2] != .string) return if (args.len >= 3) args[2] else Value.null;
    const info = parsePattern(args[0].string) orelse return args[2];
    const replacement = if (args[1] == .string) args[1].string else return args[2];
    const subject = args[2].string;

    const code = compilePattern(info.pattern, info.flags) orelse return args[2];
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return args[2];
    defer pcre2.pcre2_match_data_free_8(match_data);

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
        replacement.ptr,
        replacement.len,
        null,
        &out_len,
    );

    if (rc >= 0) return args[2];
    if (rc != pcre2.ERROR_NOMEMORY) return args[2];

    const buf = try ctx.allocator.alloc(u8, out_len);
    rc = pcre2.pcre2_substitute_8(
        code,
        subject.ptr,
        subject.len,
        0,
        sub_opts,
        match_data,
        null,
        replacement.ptr,
        replacement.len,
        buf.ptr,
        &out_len,
    );

    if (rc < 0) {
        ctx.allocator.free(buf);
        return args[2];
    }

    const result = buf[0..out_len];
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = result };
}

fn preg_split(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const info = parsePattern(args[0].string) orelse return Value.null;
    const subject = args[1].string;

    const code = compilePattern(info.pattern, info.flags) orelse return Value.null;
    defer pcre2.pcre2_code_free_8(code);

    const match_data = pcre2.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value.null;
    defer pcre2.pcre2_match_data_free_8(match_data);

    var result = try ctx.createArray();
    var offset: usize = 0;

    while (offset <= subject.len) {
        const rc = pcre2.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
        if (rc < 0) break;

        const ovector = pcre2.pcre2_get_ovector_pointer_8(match_data);
        const match_start = ovector[0];
        const match_end = ovector[1];

        try result.append(ctx.allocator, .{ .string = try ctx.createString(subject[offset..match_start]) });

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
