const std = @import("std");

// parameter names for native functions, enabling named argument resolution.
// only covers commonly-used functions - unlisted functions fall back to positional args.
// names include the $ prefix to match php convention and user-defined function param format.

pub const map = std.StaticStringMap([]const []const u8).initComptime(.{
    // strings
    .{ "substr", &.{ "$string", "$offset", "$length" } },
    .{ "str_replace", &.{ "$search", "$replace", "$subject", "$count" } },
    .{ "explode", &.{ "$separator", "$string", "$limit" } },
    .{ "implode", &.{ "$separator", "$array" } },
    .{ "join", &.{ "$separator", "$array" } },
    .{ "str_pad", &.{ "$string", "$length", "$pad_string", "$pad_type" } },
    .{ "str_repeat", &.{ "$string", "$times" } },
    .{ "str_contains", &.{ "$haystack", "$needle" } },
    .{ "str_starts_with", &.{ "$haystack", "$needle" } },
    .{ "str_ends_with", &.{ "$haystack", "$needle" } },
    .{ "strpos", &.{ "$haystack", "$needle", "$offset" } },
    .{ "stripos", &.{ "$haystack", "$needle", "$offset" } },
    .{ "strrpos", &.{ "$haystack", "$needle", "$offset" } },
    .{ "substr_count", &.{ "$haystack", "$needle", "$offset", "$length" } },
    .{ "substr_replace", &.{ "$string", "$replace", "$offset", "$length" } },
    .{ "str_split", &.{ "$string", "$length" } },
    .{ "wordwrap", &.{ "$string", "$width", "$break", "$cut_long_words" } },
    .{ "number_format", &.{ "$num", "$decimals", "$decimal_separator", "$thousands_separator" } },
    .{ "sprintf", &.{ "$format" } },
    .{ "trim", &.{ "$string", "$characters" } },
    .{ "ltrim", &.{ "$string", "$characters" } },
    .{ "rtrim", &.{ "$string", "$characters" } },
    .{ "htmlspecialchars", &.{ "$string", "$flags", "$encoding", "$double_encode" } },
    .{ "nl2br", &.{ "$string", "$use_xhtml" } },

    // arrays
    .{ "in_array", &.{ "$needle", "$haystack", "$strict" } },
    .{ "array_search", &.{ "$needle", "$haystack", "$strict" } },
    .{ "array_key_exists", &.{ "$key", "$array" } },
    .{ "array_map", &.{ "$callback", "$array" } },
    .{ "array_filter", &.{ "$array", "$callback", "$mode" } },
    .{ "array_slice", &.{ "$array", "$offset", "$length", "$preserve_keys" } },
    .{ "array_splice", &.{ "$array", "$offset", "$length", "$replacement" } },
    .{ "array_merge", &.{ "$array" } },
    .{ "array_combine", &.{ "$keys", "$values" } },
    .{ "array_chunk", &.{ "$array", "$length", "$preserve_keys" } },
    .{ "array_column", &.{ "$array", "$column_key", "$index_key" } },
    .{ "array_fill", &.{ "$start_index", "$count", "$value" } },
    .{ "array_fill_keys", &.{ "$keys", "$value" } },
    .{ "array_unique", &.{ "$array", "$flags" } },
    .{ "array_reverse", &.{ "$array", "$preserve_keys" } },
    .{ "array_pad", &.{ "$array", "$length", "$value" } },
    .{ "array_reduce", &.{ "$array", "$callback", "$initial" } },
    .{ "array_walk", &.{ "$array", "$callback", "$arg" } },
    .{ "usort", &.{ "$array", "$callback" } },
    .{ "uasort", &.{ "$array", "$callback" } },
    .{ "uksort", &.{ "$array", "$callback" } },
    .{ "compact", &.{ "$var_names" } },
    .{ "range", &.{ "$start", "$end", "$step" } },

    // types
    .{ "intval", &.{ "$value", "$base" } },
    .{ "settype", &.{ "$var", "$type" } },
    .{ "call_user_func", &.{ "$callback" } },
    .{ "version_compare", &.{ "$version1", "$version2", "$operator" } },

    // json
    .{ "json_encode", &.{ "$value", "$flags", "$depth" } },
    .{ "json_decode", &.{ "$json", "$associative", "$depth", "$flags" } },

    // math
    .{ "round", &.{ "$num", "$precision", "$mode" } },
    .{ "rand", &.{ "$min", "$max" } },
    .{ "mt_rand", &.{ "$min", "$max" } },
    .{ "base_convert", &.{ "$num", "$from_base", "$to_base" } },

    // io/filesystem
    .{ "file_get_contents", &.{ "$filename" } },
    .{ "file_put_contents", &.{ "$filename", "$data", "$flags" } },
    .{ "fopen", &.{ "$filename", "$mode" } },
    .{ "fread", &.{ "$stream", "$length" } },
    .{ "fwrite", &.{ "$stream", "$data", "$length" } },
    .{ "mkdir", &.{ "$directory", "$permissions", "$recursive" } },

    // regex
    .{ "preg_match", &.{ "$pattern", "$subject", "$matches", "$flags", "$offset" } },
    .{ "preg_match_all", &.{ "$pattern", "$subject", "$matches", "$flags", "$offset" } },
    .{ "preg_replace", &.{ "$pattern", "$replacement", "$subject", "$limit", "$count" } },
    .{ "preg_split", &.{ "$pattern", "$subject", "$limit", "$flags" } },

    // datetime
    .{ "date", &.{ "$format", "$timestamp" } },
    .{ "mktime", &.{ "$hour", "$minute", "$second", "$month", "$day", "$year" } },
    .{ "strtotime", &.{ "$datetime", "$baseTimestamp" } },

    // crypto
    .{ "password_hash", &.{ "$password", "$algo", "$options" } },
    .{ "password_verify", &.{ "$password", "$hash" } },
    .{ "hash", &.{ "$algo", "$data", "$binary" } },
    .{ "hash_hmac", &.{ "$algo", "$data", "$key", "$binary" } },
    .{ "random_int", &.{ "$min", "$max" } },

    // output
    .{ "var_dump", &.{ "$value" } },
    .{ "print_r", &.{ "$value", "$return" } },
    .{ "var_export", &.{ "$value", "$return" } },

    // session
    .{ "setcookie", &.{ "$name", "$value", "$expires_or_options", "$path", "$domain", "$secure", "$httponly" } },
});
