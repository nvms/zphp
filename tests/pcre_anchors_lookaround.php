<?php
preg_match('/^foo/', "foobar", $m);
print_r($m);
preg_match('/bar$/', "foobar", $m);
print_r($m);
preg_match('/^foo$/', "foobar", $m);
print_r($m);
preg_match('/^foo$/m', "abc\nfoo\ndef", $m);
print_r($m);

preg_match('/a{3}/', "aaab", $m);
print_r($m);
preg_match('/a{2,4}/', "aaaaab", $m);
print_r($m);
preg_match('/a{,3}/', "aaaaab", $m); // PHP allows lazy {,3}? Actually {,n} means 0-n
print_r($m);
preg_match_all('/a+/', "aaa b a baaab", $m);
print_r($m);

preg_match('/\d+/', "abc123def", $m);
print_r($m);

// greedy vs lazy
preg_match('/<.+>/', "<a><b>", $m);
print_r($m);
preg_match('/<.+?>/', "<a><b>", $m);
print_r($m);

// lookahead
preg_match_all('/\d+(?=ms)/', "100ms 200ms 300s", $m);
print_r($m);
preg_match_all('/\d+(?!ms)/', "100ms 200s 300x", $m);
print_r($m);

// lookbehind
preg_match_all('/(?<=\$)\d+/', "$10 $20 30 $99", $m);
print_r($m);
preg_match_all('/(?<!\$)\d+/', "$10 20 30", $m);
print_r($m);

// backref via \1
preg_match('/(\w+) \1/', "foo foo", $m);
print_r($m);
preg_match('/(\w+) \1/', "foo bar", $m);
var_dump($m);

// named groups
preg_match('/(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})/', "2025-01-15", $m);
print_r($m);

// preg_match_all with named
preg_match_all('/(?<word>\w+)=(?<val>\d+)/', "a=1 b=2 c=3", $m);
print_r($m);

// nested groups
preg_match('/((\w+)-(\w+))/', "foo-bar", $m);
print_r($m);

// alternatives
preg_match('/cat|dog/', "I have a dog", $m);
print_r($m);

// character classes
preg_match_all('/[a-zA-Z]+/', "Hello, World!", $m);
print_r($m);
preg_match_all('/[^a-z]+/', "abc123def456", $m);
print_r($m);

// special chars
preg_match('/[.+*?]+/', "abc.+xyz", $m);
print_r($m);

// preg_match returns 0/1/false
var_dump(preg_match('/x/', "abc"));      // 0
var_dump(preg_match('/abc/', "abcdef"));  // 1
var_dump(@preg_match('/[a/', "abc"));     // false (invalid)

// preg_match_all returns count
$n = preg_match_all('/\d/', "1a2b3c", $m);
echo $n, "\n";

// case insensitive
preg_match('/HELLO/i', "hello world", $m);
print_r($m);

// dotall
preg_match('/a.b/s', "a\nb", $m);
print_r($m);

// multiline
preg_match_all('/^line\d/m', "line1\nline2\nline3\nfoo\nline4", $m);
print_r($m);

// extended
preg_match('/foo \s+ bar/x', "foo   bar", $m);
print_r($m);

// PCRE_UNICODE
preg_match('/^.+$/u', "hello", $m);
print_r($m);

// non-capturing group
preg_match('/(?:foo)bar/', "foobar", $m);
print_r($m);

// possessive quantifiers
preg_match('/a++b/', "aaaab", $m);
print_r($m);

// atomic group (?>)
preg_match('/(?>aaa)b/', "aaab", $m);
print_r($m);

// branch reset (?|)
preg_match('/(?|(\d+)|([a-z]+))/', "abc", $m);
print_r($m);

// preg_replace
echo preg_replace('/\s+/', " ", "hello   world\tfoo"), "\n";
echo preg_replace('/(\w+)=(\d+)/', '$2:$1', "a=1 b=2"), "\n";

// preg_replace with arrays
echo preg_replace(['/a/', '/b/'], ['X', 'Y'], "abc"), "\n";
echo preg_replace(['/a/', '/b/'], 'Z', "abc"), "\n";

// preg_replace_callback
echo preg_replace_callback('/\d+/', fn($m) => intval($m[0]) * 2, "1 2 3"), "\n";

// preg_split
print_r(preg_split('/,/', "a,b,c,d"));
print_r(preg_split('/[\s,]+/', "a, b ,c , d"));

// preg_split with PREG_SPLIT_NO_EMPTY
print_r(preg_split('/,/', "a,,b,c", -1, PREG_SPLIT_NO_EMPTY));

// preg_quote
echo preg_quote("hello.world+foo"), "\n";
echo preg_quote("a-b/c", "/"), "\n";

// PREG_OFFSET_CAPTURE
preg_match('/world/', "hello world!", $m, PREG_OFFSET_CAPTURE);
print_r($m);

// PREG_UNMATCHED_AS_NULL
preg_match('/(\d+)?-(\w+)?/', "-foo", $m, PREG_UNMATCHED_AS_NULL);
print_r($m);

// preg_match returns 1 + populates $m
$ok = preg_match('/(\d+)-(\d+)/', "foo 12-34 bar", $m);
echo $ok, " ", $m[1], "/", $m[2], "\n";
