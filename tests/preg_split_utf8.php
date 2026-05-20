<?php
// regression: preg_split('//u', ...) splits a UTF-8 string at codepoint
// boundaries, not bytes. previously the empty-pattern zero-width-match path
// emitted one byte per step and advanced offset by 1, so multibyte chars
// came back as mojibake. now, when the pattern carries the 'u' modifier,
// each step emits a full UTF-8 sequence and advances by its byte length
print_r(preg_split('//u', "héllo", -1, PREG_SPLIT_NO_EMPTY));
print_r(preg_split('//u', "日本語", -1, PREG_SPLIT_NO_EMPTY));
print_r(preg_split('//u', "a😀b", -1, PREG_SPLIT_NO_EMPTY));

// non-u empty pattern still splits per byte (PHP behavior)
print_r(preg_split('//', "abc", -1, PREG_SPLIT_NO_EMPTY));

// mb_str_split is the idiomatic equivalent - sanity cross-check
var_dump(preg_split('//u', "café", -1, PREG_SPLIT_NO_EMPTY) === mb_str_split("café"));

// offset capture with UTF-8: offsets are byte positions
print_r(preg_split('//u', "ä€", -1, PREG_SPLIT_NO_EMPTY | PREG_SPLIT_OFFSET_CAPTURE));

// zero-width matches with a real pattern split cleanly (no spurious single
// chars or trailing empties): lookaround and \b boundaries
print_r(preg_split('/(?<=.)(?=.)/u', "héllo"));
print_r(preg_split('/\b/', "hello world"));
print_r(preg_split('/(?=[A-Z])/', "camelCaseWord"));
// empty pattern on empty string yields two empty pieces
print_r(preg_split('//u', ""));
print_r(preg_split('//', ""));
