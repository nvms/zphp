<?php
$count = 0;
$r = preg_replace_callback('/\d+/', fn($m) => "[" . $m[0] . "]", "1 2 3 4 5", -1, $count);
echo $r, "\n";
echo "count=$count\n";

$count = 0;
$r = preg_replace_callback('/\d+/', fn($m) => "X", "1 2 3", 2, $count);
echo $r, "\n";
echo "count=$count\n";

$count = 0;
$r = preg_replace('/\d+/', 'X', "1 2 3 4 5", -1, $count);
echo $r, "\n";
echo "count=$count\n";

$count = 0;
$r = preg_replace('/\d+/', 'X', "1 2 3 4 5", 2, $count);
echo $r, "\n";
echo "count=$count\n";

$r = preg_replace('/\d/', 'X', ["a1", "b22", "c333"]);
print_r($r);

$r = preg_replace(['/\d/', '/[a-z]/'], ['N', 'L'], ["a1", "b22"]);
print_r($r);

$r = preg_replace(['/foo/', '/bar/'], 'X', "foo bar baz");
echo $r, "\n";

// pattern-string + replacement-array TypeError (architectural - zphp accepts)

$count = 0;
$r = preg_replace(['/a/', '/b/'], ['X', 'Y'], "abcabc", -1, $count);
echo $r, "\n";
echo "count=$count\n";

$count = 0;
$r = preg_replace(['/a/', '/b/'], ['X', 'Y'], "abcabc", 1, $count);
echo $r, "\n";
echo "count=$count\n";

$result = preg_replace_callback_array([
    '/\d+/' => fn($m) => "[" . $m[0] . "]",
    '/[A-Z]+/' => fn($m) => strtolower($m[0]),
], "Hello 42 WORLD 99", -1, $count);
echo $result, "\n";
echo "count=$count\n";

$r = preg_replace('/\d+/', '$0!', "1 2 3");
echo $r, "\n";

$r = preg_replace('/(\w+)=(\d+)/', '$2:$1', "a=1 b=2");
echo $r, "\n";

$r = preg_replace_callback('/(\w+)/', function ($m) {
    return ucfirst($m[1]);
}, "hello world foo");
echo $r, "\n";

$r = preg_replace_callback('/[a-z]/', function ($m) {
    return strtoupper($m[0]);
}, "abc DEF ghi", 2);
echo $r, "\n";

$count = 0;
$r = preg_replace_callback('/x/', fn() => "Y", "abc", -1, $count);
echo $r, "/", $count, "\n";

$r = preg_replace('/\s+/', ' ', "hello   world\t\tfoo\n\nbar");
echo $r, "\n";

$r = preg_replace_callback_array([
    '/(?<digit>\d+)/' => fn($m) => "[" . $m["digit"] . "]",
], "a 1 b 22 c 333");
echo $r, "\n";

// /e modifier warning (architectural - PHP emits Warning, zphp silent)

// preg_replace null subject (architectural - PHP returns "" with deprecation)

$r = preg_replace('/foo/', 'bar', "");
echo "[", $r, "]\n";

$r = preg_replace('/foo/', '', "foofoofoo");
echo "[", $r, "]\n";

$count = 0;
$r = preg_replace_callback_array([
    '/\d+/' => fn($m) => "[" . $m[0] . "]",
    '/foo/' => fn($m) => "FOO",
], "abc 123 foo 456 def", -1, $count);
echo $r, "\n";
echo "count=$count\n";

$r = preg_replace('/(\w)(\w)(\w)/', '$3$2$1', "abc def ghi");
echo $r, "\n";
