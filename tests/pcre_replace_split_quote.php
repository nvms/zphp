<?php
// preg_match_all PATTERN_ORDER (default)
preg_match_all('/(\w+)=(\d+)/', 'a=1 b=2 c=3', $m);
print_r($m);

preg_match_all('/(\w+)=(\d+)/', 'a=1 b=2 c=3', $m, PREG_PATTERN_ORDER);
print_r($m);

preg_match_all('/(\w+)=(\d+)/', 'a=1 b=2 c=3', $m, PREG_SET_ORDER);
print_r($m);

// named captures
preg_match_all('/(?<k>\w+)=(?<v>\d+)/', 'a=1 b=2', $m);
print_r($m);

preg_match_all('/(?<k>\w+)=(?<v>\d+)/', 'a=1 b=2', $m, PREG_SET_ORDER);
print_r($m);

// preg_replace_callback with named captures
echo preg_replace_callback('/(?<word>\w+)/', function ($m) {
    return strtoupper($m["word"]);
}, "hello world"), "\n";

// preg_replace_callback returning empty
echo preg_replace_callback('/(\d+)/', fn($m) => "<{$m[1]}>", "a 1 b 22 c 333"), "\n";

// preg_replace_callback with limit
echo preg_replace_callback('/(\d)/', fn($m) => "X", "a1b2c3d4", 2), "\n";

// preg_replace_callback_array
echo preg_replace_callback_array([
    '/\d+/' => fn($m) => "[" . $m[0] . "]",
    '/[a-z]+/' => fn($m) => strtoupper($m[0]),
], "a 1 b 22 c 333"), "\n";

// preg_split basic
print_r(preg_split('/[\s,]+/', "hello world,foo bar"));

// preg_split with capture groups (default flag 0 - doesn't include captures)
print_r(preg_split('/(\s)/', "hello world foo"));

// preg_split with PREG_SPLIT_DELIM_CAPTURE
print_r(preg_split('/(\s+)/', "hello   world foo", -1, PREG_SPLIT_DELIM_CAPTURE));

// preg_split with PREG_SPLIT_NO_EMPTY
print_r(preg_split('/,/', "a,,b,c,,", -1, PREG_SPLIT_NO_EMPTY));

// preg_split with limit
print_r(preg_split('/,/', "a,b,c,d,e", 3));

// preg_split with PREG_SPLIT_OFFSET_CAPTURE
print_r(preg_split('/,/', "abc,def,gh", -1, PREG_SPLIT_OFFSET_CAPTURE));

// preg_quote
echo preg_quote("hello.world+foo*bar"), "\n";
echo preg_quote("/path/to/file", "/"), "\n";
echo preg_quote("a-b-c", "-"), "\n";
echo preg_quote("a#b#c", "#"), "\n";
echo preg_quote('special: . \ + * ? [ ^ ] $ ( ) { } = ! < > | : - #'), "\n";

// preg_match with offset capture
preg_match('/world/', 'hello world', $m, PREG_OFFSET_CAPTURE);
print_r($m);

preg_match_all('/(\d+)/', "a 12 b 345 c 6", $m, PREG_OFFSET_CAPTURE);
print_r($m);

preg_match_all('/(\d+)/', "a 12 b 345 c 6", $m, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
print_r($m);

// PREG_UNMATCHED_AS_NULL
preg_match('/(\d+)?-(\w+)?/', '-foo', $m, PREG_UNMATCHED_AS_NULL);
print_r($m);

preg_match_all('/(\d+)?-(\w+)?/', '-foo -bar 12-', $m, PREG_UNMATCHED_AS_NULL);
print_r($m);

// preg_grep
print_r(preg_grep('/^\d+$/', ["1", "abc", "23", "x4", "5"]));
print_r(preg_grep('/^\d+$/', ["1", "abc", "23", "x4", "5"], PREG_GREP_INVERT));

// pattern modifiers
preg_match('/HELLO/i', 'hello world', $m);
print_r($m);

preg_match('/^foo$/m', "abc\nfoo\nbar", $m);
print_r($m);

preg_match('/a.b/s', "a\nb", $m);
print_r($m);

// preg_replace with arrays
echo preg_replace(['/a/', '/b/'], ['X', 'Y'], "abc"), "\n";
echo preg_replace(['/a/', '/b/'], 'Z', "abc"), "\n";

// preg_replace with backref
echo preg_replace('/(\w+)=(\d+)/', '$2:$1', 'a=1 b=2'), "\n";
echo preg_replace('/(\w+)=(\d+)/', '\2:\1', 'a=1 b=2'), "\n";
echo preg_replace('/(?<key>\w+)=(?<val>\d+)/', '${key}<-${val}', 'a=1 b=2'), "\n";

// preg_match returns int
$r = preg_match('/x/', 'abc');
var_dump($r); // int(0)

$r = preg_match('/abc/', 'xabcy');
var_dump($r); // int(1)

// invalid pattern
$r = @preg_match('/[a/', 'abc');
var_dump($r); // false

// preg_match_all returns int (count)
$n = preg_match_all('/\d/', 'a1b2c3', $m);
echo $n, "\n";
