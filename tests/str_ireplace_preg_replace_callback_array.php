<?php
echo str_ireplace("hello", "HI", "Hello World"), "\n";
echo str_ireplace("WORLD", "earth", "hello world"), "\n";
echo str_ireplace(["a", "b"], "X", "ABC ABC"), "\n";
echo str_ireplace(["A", "B", "C"], ["1", "2", "3"], "ABC abc ABC"), "\n";

$count = 0;
$r = str_ireplace("X", "Y", "xxXX", $count);
echo $r, " count=", $count, "\n";

$count = 0;
$r = str_ireplace(["a", "b"], "*", "abc ABC AbC", $count);
echo $r, " count=", $count, "\n";

echo str_ireplace([], "X", "test"), "\n";
echo str_ireplace("", "X", "test"), "\n";

echo preg_replace_callback('/\d+/', fn($m) => $m[0] * 2, "a1 b2 c3"), "\n";

echo preg_replace_callback('/([a-z]+)(\d+)/', fn($m) => $m[1] . "-" . $m[2], "abc123 def456"), "\n";

echo preg_replace_callback('/\d/', function ($m) {
    return strval(intval($m[0]) + 1);
}, "1 2 3 4 5"), "\n";

$count = 0;
$r = preg_replace_callback('/\w+/', fn($m) => strtoupper($m[0]), "hello world", -1, $count);
echo $r, " count=", $count, "\n";

$r = preg_replace_callback_array([
    '/[aeiou]/' => fn($m) => strtoupper($m[0]),
    '/\d/' => fn($m) => $m[0] * 10,
], "hello 5 world 3");
echo $r, "\n";

$r = preg_replace_callback_array([
    '/foo/' => fn($m) => "FOO!",
    '/bar/' => fn($m) => "BAR!",
], "foo bar foo");
echo $r, "\n";

$count = 0;
$r = preg_replace_callback_array([
    '/\d/' => fn($m) => "[" . $m[0] . "]",
    '/[a-z]/' => fn($m) => strtoupper($m[0]),
], "a1b2c3", -1, $count);
echo $r, " count=", $count, "\n";

echo preg_replace_callback(['/a/', '/b/'], fn($m) => strtoupper($m[0]), ["a1", "b2", "abc"])[0], "\n";

print_r(preg_replace_callback('/\d+/', fn($m) => "[" . $m[0] . "]", ["a1", "b22", "c"]));

echo preg_replace_callback('/^/', fn($m) => ">>> ", "hello"), "\n";

echo preg_replace_callback('/x/', fn($m) => "Y", "hello"), "\n";

$counter = 0;
$r = preg_replace_callback('/\w/', function ($m) use (&$counter) {
    $counter++;
    return $m[0];
}, "abc 123");
echo "iters=", $counter, "\n";

echo preg_replace_callback('/(\w+)/u', fn($m) => strrev($m[0]), "hello world"), "\n";

echo preg_replace_callback('/(\d+)/', function ($m) {
    return ((int)$m[1]) % 2 === 0 ? "[$m[1]]" : $m[1];
}, "1 2 3 4 5"), "\n";

echo preg_replace_callback_array([], "unchanged"), "\n";

$r = preg_replace_callback_array(['/a/' => fn($m) => "X"], ["abc", "aab"]);
print_r($r);

class Replacer {
    public function go(array $m): string {
        return strtoupper($m[0]);
    }
}

$obj = new Replacer;
echo preg_replace_callback('/\w+/', [$obj, "go"], "hello world"), "\n";

$callable = "strtoupper";
echo str_ireplace("foo", "FOO", "Foo Bar"), "\n";

echo str_ireplace(["a", "b", "c"], ["X"], "abc"), "\n";
echo str_ireplace(["a", "b"], "x", "AAA BBB"), "\n";

echo preg_replace_callback('/_(\w)/', fn($m) => strtoupper($m[1]), "snake_case_var"), "\n";

echo preg_replace_callback('/[A-Z]/', fn($m) => "_" . strtolower($m[0]), "camelCaseVar"), "\n";

$tokens = [];
preg_replace_callback('/[a-z]+|\d+/', function ($m) use (&$tokens) {
    $tokens[] = $m[0];
    return $m[0];
}, "abc123def");
print_r($tokens);

echo preg_replace_callback('/./', fn($m) => $m[0] . $m[0], "abc"), "\n";

echo preg_replace_callback('/\W+/', fn($m) => " ", "hello,world.foo!bar"), "\n";

$total = 0;
$r = preg_replace_callback('/\d+/', function ($m) use (&$total) {
    $total += (int)$m[0];
    return $m[0];
}, "1 2 3 4 5");
echo "total=", $total, "\n";

$r = preg_replace_callback_array([
    '/foo/' => fn($m) => "X",
], "no match here");
echo $r === "no match here" ? "y" : "n", "\n";

$r = preg_replace_callback_array([
    '/(\w+)/' => fn($m) => strlen($m[1]) . ":" . $m[1],
], "the quick brown fox");
echo $r, "\n";

echo preg_replace_callback('/[a-z]/i', fn($m) => "[$m[0]]", "AbC123"), "\n";

class Multi {
    public string $prefix = ">>";
    public function transform(array $m): string {
        return $this->prefix . $m[0];
    }
}
$m = new Multi;
echo preg_replace_callback('/\w+/', [$m, "transform"], "hello world"), "\n";
