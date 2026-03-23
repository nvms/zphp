const std = @import("std");
const Value = @import("../runtime/value.zig").Value;
const PhpArray = @import("../runtime/value.zig").PhpArray;
const NativeContext = @import("../runtime/vm.zig").NativeContext;
const RuntimeError = error{ RuntimeError, OutOfMemory };

const c = @cImport({
    @cDefine("PCRE2_CODE_UNIT_WIDTH", "8");
    @cInclude("pcre2.h");
});

pub const entries = .{
    .{ "preg_match", preg_match },
    .{ "preg_match_all", preg_match_all },
    .{ "preg_replace", preg_replace },
    .{ "preg_split", preg_split },
};

const PatternInfo = struct {
    pattern: []const u8,
    flags: u32,
    global: bool,
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
    var global = false;
    for (modifiers) |m| {
        switch (m) {
            'i' => flags |= c.PCRE2_CASELESS,
            'm' => flags |= c.PCRE2_MULTILINE,
            's' => flags |= c.PCRE2_DOTALL,
            'x' => flags |= c.PCRE2_EXTENDED,
            'u' => flags |= c.PCRE2_UTF,
            'g' => global = true,
            else => {},
        }
    }
    return .{ .pattern = pattern, .flags = flags, .global = global };
}

fn compilePattern(pattern: []const u8, flags: u32) ?*c.pcre2_code_8 {
    var err_code: c_int = 0;
    var err_offset: usize = 0;
    const code = c.pcre2_compile_8(
        pattern.ptr,
        pattern.len,
        flags,
        &err_code,
        &err_offset,
        null,
    );
    return code;
}

fn preg_match(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = 0 };
    const info = parsePattern(args[0].string) orelse return Value{ .int = 0 };
    const subject = args[1].string;

    const code = compilePattern(info.pattern, info.flags) orelse return Value{ .int = 0 };
    defer c.pcre2_code_free_8(code);

    const match_data = c.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value{ .int = 0 };
    defer c.pcre2_match_data_free_8(match_data);

    const rc = c.pcre2_match_8(code, subject.ptr, subject.len, 0, 0, match_data, null);
    if (rc < 0) return .{ .int = 0 };

    if (args.len >= 3 and args[2] == .array) {
        const matches_arr = args[2].array;
        const ovector = c.pcre2_get_ovector_pointer_8(match_data);
        const count: usize = @intCast(rc);

        // clear existing entries
        matches_arr.entries.items.len = 0;
        matches_arr.next_int_key = 0;

        for (0..count) |i| {
            const start = ovector[i * 2];
            const end = ovector[i * 2 + 1];
            if (start == std.math.maxInt(usize) or end == std.math.maxInt(usize)) {
                try matches_arr.append(ctx.allocator, .{ .string = "" });
            } else {
                try matches_arr.append(ctx.allocator, .{ .string = try ctx.createString(subject[start..end]) });
            }
        }
    }

    return .{ .int = 1 };
}

fn preg_match_all(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .{ .int = 0 };
    const info = parsePattern(args[0].string) orelse return Value{ .int = 0 };
    const subject = args[1].string;

    const code = compilePattern(info.pattern, info.flags) orelse return Value{ .int = 0 };
    defer c.pcre2_code_free_8(code);

    const match_data = c.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value{ .int = 0 };
    defer c.pcre2_match_data_free_8(match_data);

    var capture_count: u32 = 0;
    _ = c.pcre2_pattern_info_8(code, c.PCRE2_INFO_CAPTURECOUNT, &capture_count);
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
        const rc = c.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
        if (rc < 0) break;

        const ovector = c.pcre2_get_ovector_pointer_8(match_data);
        const count: usize = @intCast(rc);

        for (0..group_count) |i| {
            if (i < count) {
                const start = ovector[i * 2];
                const end = ovector[i * 2 + 1];
                if (start == std.math.maxInt(usize) or end == std.math.maxInt(usize)) {
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

    if (args.len >= 3 and args[2] == .array) {
        const out = args[2].array;
        out.entries.items.len = 0;
        out.next_int_key = 0;
        for (group_arrays.items) |arr| {
            try out.append(ctx.allocator, .{ .array = arr });
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
    defer c.pcre2_code_free_8(code);

    const match_data = c.pcre2_match_data_create_from_pattern_8(code, null) orelse return args[2];
    defer c.pcre2_match_data_free_8(match_data);

    const sub_opts: u32 = c.PCRE2_SUBSTITUTE_OVERFLOW_LENGTH | c.PCRE2_SUBSTITUTE_GLOBAL;

    // first call to get required length
    var out_len: usize = 0;
    var rc = c.pcre2_substitute_8(
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

    if (rc >= 0) {
        // no matches, return original
        return args[2];
    }

    if (rc != c.PCRE2_ERROR_NOMEMORY) return args[2];

    const buf = try ctx.allocator.alloc(u8, out_len);
    rc = c.pcre2_substitute_8(
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
    if (result.len < buf.len) {
        // shrink - but we track the original allocation for cleanup
    }
    try ctx.strings.append(ctx.allocator, buf);
    return .{ .string = result };
}

fn preg_split(ctx: *NativeContext, args: []const Value) RuntimeError!Value {
    if (args.len < 2 or args[0] != .string or args[1] != .string) return .null;
    const info = parsePattern(args[0].string) orelse return Value.null;
    const subject = args[1].string;

    const code = compilePattern(info.pattern, info.flags) orelse return Value.null;
    defer c.pcre2_code_free_8(code);

    const match_data = c.pcre2_match_data_create_from_pattern_8(code, null) orelse return Value.null;
    defer c.pcre2_match_data_free_8(match_data);

    var result = try ctx.createArray();
    var offset: usize = 0;

    while (offset <= subject.len) {
        const rc = c.pcre2_match_8(code, subject.ptr, subject.len, offset, 0, match_data, null);
        if (rc < 0) break;

        const ovector = c.pcre2_get_ovector_pointer_8(match_data);
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
