<?php
echo preg_replace_callback('/(?<word>\w+)/', function ($m) {
    return strtoupper($m["word"]);
}, "hello world"), "\n";

echo preg_replace_callback('/(?<key>\w+)=(?<val>\w+)/', function ($m) {
    return $m["key"] . ":" . strtoupper($m["val"]);
}, "a=foo b=bar c=baz"), "\n";

$result = preg_replace_callback_array([
    '/\d+/' => fn($m) => "[" . $m[0] . "]",
    '/[A-Z]+/' => fn($m) => strtolower($m[0]),
    '/[a-z]+/' => fn($m) => strtoupper($m[0]),
], "Hello 42 WORLD 99 foo");
echo $result, "\n";

echo preg_replace_callback('/\d+/', fn($m) => intval($m[0]) * 2, "1 2 3 4 5", 3), "\n";

$count = 0;
preg_match_all('/\d+/', "1 22 333 4444", $m);
foreach ($m[0] as $n) $count += intval($n);
echo $count, "\n";

preg_match_all('/(\w+)=(\d+)/', "a=1 b=2 c=3", $m);
print_r($m);

preg_match_all('/(\w+)=(\d+)/', "a=1 b=2 c=3", $m, PREG_SET_ORDER);
print_r($m);

preg_match_all('/(\w+)=(\d+)/', "a=1 b=2 c=3", $m, PREG_PATTERN_ORDER | PREG_OFFSET_CAPTURE);
print_r($m);

preg_match_all('/(?<k>\w+)=(?<v>\d+)/', "a=1 b=2", $m);
print_r($m);

preg_match_all('/(?<k>\w+)=(?<v>\d+)/', "a=1 b=2", $m, PREG_SET_ORDER);
print_r($m);

preg_match_all('/(\d+)?-(\w+)?/', "-foo 12-bar 34-", $m, PREG_UNMATCHED_AS_NULL);
print_r($m);

preg_match_all('/(\d+)?-(\w+)?/', "-foo 12-bar 34-", $m, PREG_SET_ORDER | PREG_UNMATCHED_AS_NULL);
print_r($m);

preg_match_all('/(\d+)?-(\w+)?/', "-foo 12-bar", $m, PREG_PATTERN_ORDER | PREG_OFFSET_CAPTURE | PREG_UNMATCHED_AS_NULL);
print_r($m);

$r = preg_match_all('/\d+/', "abc", $m);
echo $r, "\n";
print_r($m);

$r = preg_match_all('/\d+/', "1 2 3", $m);
echo $r, "\n";

$r = preg_match_all('/\d+/', "abc def", $m, PREG_SET_ORDER);
echo $r, "\n";
print_r($m);

$count = preg_match_all('/\d+/', "1 22 333 4444", $m);
foreach ($m[0] as $i => $match) {
    echo "$i: $match\n";
}

echo preg_replace_callback('/\d+/', function ($m) {
    static $n = 0;
    $n++;
    return "[$n:{$m[0]}]";
}, "a 1 b 2 c 3"), "\n";

echo preg_replace_callback_array([
    '/foo/' => fn() => "FOO",
    '/bar/' => fn() => "BAR",
    '/baz/' => fn() => "BAZ",
], "foo bar baz foo"), "\n";

class Counter { public int $n = 0; }
$c = new Counter;
$result = preg_replace_callback('/\d+/', function ($m) use ($c) {
    $c->n++;
    return "X";
}, "1 2 3 4");
echo $result, " count=", $c->n, "\n";

echo preg_replace_callback('/(\w+)/', function ($m) {
    return ucfirst($m[1]);
}, "hello world foo"), "\n";

preg_match_all('/(\w+)/', "abc def", $m);
print_r($m[0]);
print_r($m[1]);

$lines = "line1\nline2\nline3";
preg_match_all('/^line\d+/m', $lines, $m);
print_r($m);

preg_match_all('/(\w)/u', "héllo", $m);
print_r($m);

$urls = "Visit http://a.com or https://b.org and ftp://c.net for more.";
preg_match_all('/(https?|ftp):\/\/([^\s]+)/', $urls, $m, PREG_SET_ORDER);
foreach ($m as $match) {
    echo $match[1], "://", $match[2], "\n";
}

$html = "<a href='http://x.com'>X</a> <b>Bold</b>";
preg_match_all('/<(\w+)[^>]*>(.*?)<\/\1>/', $html, $m);
print_r($m);
