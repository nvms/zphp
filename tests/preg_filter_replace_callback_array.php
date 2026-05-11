<?php
$r = preg_filter('/(\d+)/', '[$1]', ["one", "two3", "three4"]);
print_r($r);

$r = preg_filter('/(\d+)/', '<num>', "abc 12 def");
echo $r, "\n";

$r = preg_filter('/x/', 'X', ["yes", "no"]);
print_r($r);

$result = preg_replace_callback('/(?P<word>\w+)/', function ($m) {
    return strtoupper($m["word"]);
}, "hello world");
echo $result, "\n";

$result = preg_replace_callback_array([
    '/\d+/' => fn($m) => "NUM(" . $m[0] . ")",
    '/[a-z]+/' => fn($m) => "WORD(" . $m[0] . ")",
], "abc 123 def 456");
echo $result, "\n";

echo preg_replace('/(\w+)/', '[$1]', "hello world"), "\n";
echo preg_replace('/(\w+)/', '[${1}]', "hello world"), "\n";
echo preg_replace('/(\w+)/', '<$0>', "hello world"), "\n";
echo preg_replace('/(\w+) (\w+)/', '$2 $1', "first second"), "\n";

echo preg_replace_callback('/(\d+)/', fn($m) => $m[1] * 2, "a 3 b 5"), "\n";

$result = preg_replace_callback(['/abc/', '/def/'], fn($m) => "[" . $m[0] . "]", "abc def ghi");
echo $result, "\n";

$result = preg_replace(['/a/', '/b/', '/c/'], ['1', '2', '3'], "abc");
echo $result, "\n";

$result = preg_replace_callback('/(?P<a>\w+)/', function ($m) {
    return "[" . $m['a'] . "/" . $m[0] . "]";
}, "alpha");
echo $result, "\n";

$counts = 0;
$r = preg_replace('/\d/', 'X', "a1b2c3", -1, $counts);
echo $r, " $counts\n";

$counts = 0;
$r = preg_replace_callback('/\w/', fn($m) => "[$m[0]]", "abc", -1, $counts);
echo $r, " $counts\n";

$result = preg_replace_callback('/\b(\w+)\b/', function ($m) {
    static $i = 0;
    return $m[1] . "(" . (++$i) . ")";
}, "alpha beta gamma");
echo $result, "\n";

echo preg_replace('/(\w+)/', '\1-\1', "hi"), "\n";

echo preg_replace('/(\w+)/i', '<$0>', "Hello"), "\n";

$result = preg_replace_callback('/(?<=#)(\w+)/', function ($m) {
    return strtoupper($m[1]);
}, "hello #world #foo");
echo $result, "\n";

$arr = ["one1", "two2", "three3"];
$out = preg_replace_callback_array([
    '/\d/' => fn($m) => "(N)",
    '/[aeiou]/' => fn($m) => "(V)",
], $arr);
print_r($out);
