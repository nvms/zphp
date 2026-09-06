const std = @import("std");

// natives whose first parameter is by reference: the caller's array is passed
// in place and the native mutates it. the compiler separates a shared array
// before the call, and the VM treats the native's hold on it as an alias of
// the reference set rather than a value copy
const arg0_by_ref = [_][]const u8{
    "sort",         "rsort",      "asort",                "arsort",          "ksort",      "krsort",    "natsort",     "natcasesort",
    "usort",        "uasort",     "uksort",               "shuffle",         "array_push", "array_pop", "array_shift", "array_unshift",
    "array_splice", "array_walk", "array_walk_recursive", "array_multisort", "end",        "reset",     "next",        "prev",
    "each",
};

// an unqualified builtin call inside a namespace resolves to the namespaced
// name at compile time (e.g. Foo\Bar\array_shift) but falls back to the
// global native at runtime, so match on the basename
pub fn arg0IsByRef(name: []const u8) bool {
    const base = if (std.mem.lastIndexOfScalar(u8, name, '\\')) |i| name[i + 1 ..] else name;
    for (arg0_by_ref) |candidate| if (std.ascii.eqlIgnoreCase(candidate, base)) return true;
    return false;
}

// All output positions implemented by the native library. Check these before
// entering native code: setCallerVar is too late for callbacks and in-place
// mutations (and cannot return a binding error).
pub fn isByRef(name: []const u8, index: usize) bool {
    const base = if (std.mem.lastIndexOfScalar(u8, name, '\\')) |i| name[i + 1 ..] else name;
    if (index == 0 and arg0IsByRef(base)) return true;
    const Output = struct { name: []const u8, index: usize };
    const outputs = [_]Output{
        .{ .name = "pcntl_wait", .index = 0 },
        .{ .name = "parse_str", .index = 1 },
        .{ .name = "mb_parse_str", .index = 1 },
        .{ .name = "system", .index = 1 },
        .{ .name = "passthru", .index = 1 },
        .{ .name = "exec", .index = 1 },
        .{ .name = "pcntl_waitpid", .index = 1 },
        .{ .name = "curl_multi_exec", .index = 1 },
        .{ .name = "curl_multi_info_read", .index = 1 },
        .{ .name = "openssl_random_pseudo_bytes", .index = 1 },
        .{ .name = "preg_match", .index = 2 },
        .{ .name = "preg_match_all", .index = 2 },
        .{ .name = "similar_text", .index = 2 },
        .{ .name = "is_callable", .index = 2 },
        .{ .name = "getopt", .index = 2 },
        .{ .name = "exec", .index = 2 },
        .{ .name = "proc_open", .index = 2 },
        .{ .name = "pcntl_sigprocmask", .index = 2 },
        .{ .name = "ldap_get_option", .index = 2 },
        .{ .name = "str_replace", .index = 3 },
        .{ .name = "str_ireplace", .index = 3 },
        .{ .name = "preg_replace_callback_array", .index = 3 },
        .{ .name = "preg_replace", .index = 4 },
        .{ .name = "preg_filter", .index = 4 },
        .{ .name = "preg_replace_callback", .index = 4 },
        .{ .name = "openssl_encrypt", .index = 5 },
    };
    for (outputs) |output| {
        if (index == output.index and std.ascii.eqlIgnoreCase(base, output.name)) return true;
    }
    if (std.ascii.eqlIgnoreCase(base, "stream_select")) return index < 3;
    if (std.ascii.eqlIgnoreCase(base, "array_multisort")) return true;
    if (std.ascii.eqlIgnoreCase(base, "sscanf") or std.ascii.eqlIgnoreCase(base, "fscanf") or std.ascii.eqlIgnoreCase(base, "mb_convert_variables")) return index >= 2;
    return false;
}

// every native with at least one output position, lowercase. the argument
// guard consults this on every cold call site, so it is a keyed lookup rather
// than a walk over the position tables above
const by_ref_names = std.StaticStringMap(void).initComptime(.{
    .{"sort"},              .{"rsort"},           .{"asort"},                 .{"arsort"},                      .{"ksort"},
    .{"krsort"},            .{"natsort"},         .{"natcasesort"},           .{"usort"},                       .{"uasort"},
    .{"uksort"},            .{"shuffle"},         .{"array_push"},            .{"array_pop"},                   .{"array_shift"},
    .{"array_unshift"},     .{"array_splice"},    .{"array_walk"},            .{"array_walk_recursive"},        .{"array_multisort"},
    .{"end"},               .{"reset"},           .{"next"},                  .{"prev"},                        .{"each"},
    .{"pcntl_wait"},        .{"parse_str"},       .{"system"},                .{"passthru"},                    .{"exec"},
    .{"pcntl_waitpid"},     .{"curl_multi_exec"}, .{"curl_multi_info_read"},  .{"openssl_random_pseudo_bytes"}, .{"preg_match"},
    .{"preg_match_all"},    .{"similar_text"},    .{"is_callable"},           .{"getopt"},                      .{"proc_open"},
    .{"pcntl_sigprocmask"}, .{"ldap_get_option"}, .{"str_replace"},           .{"str_ireplace"},                .{"preg_replace_callback_array"},
    .{"preg_replace"},      .{"preg_filter"},     .{"preg_replace_callback"}, .{"openssl_encrypt"},             .{"stream_select"},
    .{"sscanf"},            .{"fscanf"},          .{"mb_convert_variables"},  .{"mb_parse_str"},
});

pub fn hasByRefParams(name: []const u8) bool {
    const base = if (std.mem.lastIndexOfScalar(u8, name, '\\')) |i| name[i + 1 ..] else name;
    var lower: [64]u8 = undefined;
    if (base.len > lower.len) return false;
    for (base, 0..) |c, i| lower[i] = std.ascii.toLower(c);
    return by_ref_names.has(lower[0..base.len]);
}

test "hasByRefParams agrees with the position tables" {
    const names = [_][]const u8{ "sort", "PREG_MATCH", "Vendor\\str_replace", "sscanf", "fscanf", "mb_parse_str", "stream_select", "array_multisort", "openssl_encrypt", "strlen", "count", "App\\array_map" };
    for (names) |name| {
        var expected = false;
        for (0..6) |i| if (isByRef(name, i)) {
            expected = true;
        };
        try std.testing.expectEqual(expected, hasByRefParams(name));
    }
}

test "native output parameter positions" {
    try std.testing.expect(isByRef("preg_match", 2));
    try std.testing.expect(!isByRef("preg_match", 1));
    try std.testing.expect(isByRef("Vendor\\PREG_REPLACE", 4));
    try std.testing.expect(isByRef("preg_replace_callback_array", 3));
    try std.testing.expect(!isByRef("preg_replace_callback_array", 4));
    try std.testing.expect(isByRef("sscanf", 8));
    try std.testing.expect(!isByRef("sscanf", 1));
    try std.testing.expect(isByRef("mb_convert_variables", 3));
    try std.testing.expect(isByRef("mb_parse_str", 1));
    try std.testing.expect(!isByRef("mb_parse_str", 0));
    try std.testing.expect(isByRef("fscanf", 2));
    try std.testing.expect(!isByRef("fscanf", 1));
    try std.testing.expect(isByRef("stream_select", 2));
    try std.testing.expect(!isByRef("stream_select", 3));
    try std.testing.expect(isByRef("SORT", 0));
    try std.testing.expect(!isByRef("strlen", 0));
}
