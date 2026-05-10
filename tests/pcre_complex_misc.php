<?php
// PCRE complex patterns
preg_match('/^(?<protocol>https?):\/\/(?<host>[^\/]+)(?<path>.*)$/', "https://example.com/path/to/page", $m);
echo $m['protocol'], "://", $m['host'], $m['path'], "\n";

// PCRE named conditional
preg_match('/(?(DEFINE)(?<word>\w+))(?<first>(?&word)) (?<second>(?&word))/', "hello world", $m);
echo $m['first'], "/", $m['second'], "\n";

// PCRE backreferences
preg_match('/(\w+) \1/', "hello hello", $m);
echo $m[0], "\n";
preg_match('/(?<w>\w+) \k<w>/', "foo foo", $m);
echo $m[0], ":", $m['w'], "\n";

// PCRE recursion
preg_match('/^([a-z]+(?:\s\1)*)$/', "abc abc abc", $m);
echo isset($m[0]) ? "rec-ok" : "no", "\n";

// PCRE atomic
preg_match('/(?>a+)b/', "aaab", $m);
echo $m[0] ?? "no", "\n";

// PCRE possessive
preg_match('/a++b/', "aaab", $m);
echo $m[0] ?? "no", "\n";

// PCRE2 verb \K
preg_match('/foo\Kbar/', "foobar", $m);
echo $m[0] ?? "no", "\n"; // bar (\K resets match start)

// (*FAIL)
$r = preg_match('/abc(*FAIL)/', "abc");
var_dump($r); // 0 - never matches

// (*COMMIT)
preg_match('/a(*COMMIT)b/', "ab", $m);
echo $m[0] ?? "no", "\n";

// PCRE modifier flags combined
preg_match('/HELLO/im', "Hello\nworld", $m);
echo $m[0] ?? "no", "\n";

preg_match_all('/(\w+)/u', "Hello мир 你好", $m);
print_r($m[1]);

// regex callback with multiple matches
$r = preg_replace_callback('/(\d+)/', function ($m) {
    return "[" . ((int)$m[1] * 2) . "]";
}, "a1 b22 c333");
echo $r, "\n";

// preg_replace with substring backref
echo preg_replace('/(\w+)@(\w+)/', '$2 at $1', 'user@host other@box'), "\n";

// PHP's PCRE substitute behavior on $$ differs from PCRE2's standard (architectural)

// named groups in callback
$r = preg_replace_callback('/(?<key>\w+)=(?<val>\w+)/', fn($m) => "{$m['key']}:{$m['val']}", "a=1 b=2");
echo $r, "\n";

// preg_split with empty pattern - PHP errors? actually splits between every char
print_r(preg_split('//', "abc", -1, PREG_SPLIT_NO_EMPTY));

// preg_split with PREG_SPLIT_OFFSET_CAPTURE
print_r(preg_split('/,/', "a,b,c", -1, PREG_SPLIT_OFFSET_CAPTURE));

// preg_quote
echo preg_quote("a.b*c?d", "/"), "\n";
echo preg_quote(""), "|\n";

// PHP emits warning on invalid pattern (architectural)
@preg_match('/[/', 'abc');
$err = preg_last_error();
echo $err !== 0 ? "err\n" : "no\n";
echo strlen(preg_last_error_msg()) > 0 ? "msg-ok\n" : "no\n";

// reset with valid
preg_match('/abc/', 'abc');
echo preg_last_error() === 0 ? "clear\n" : "still", "\n";

// preg_grep with keys preserved
$arr = ["a" => "abc", "b" => "123", "c" => "xyz"];
print_r(preg_grep('/^\d+$/', $arr));

// preg_match return
var_dump(preg_match('/b/', 'abc'));
var_dump(preg_match('/x/', 'abc'));
var_dump(@preg_match('/[/', 'abc')); // false on error
