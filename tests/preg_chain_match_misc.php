<?php
// preg_match_all with PREG_SET_ORDER + PREG_OFFSET_CAPTURE combined
$s = "2024-06-15 and 2024-12-25";
preg_match_all('/(\d{4})-(\d{2})-(\d{2})/', $s, $m, PREG_SET_ORDER | PREG_OFFSET_CAPTURE);
foreach ($m as $set) {
    echo $set[0][0], "@", $set[0][1], "|";
    echo $set[1][0], ",", $set[2][0], ",", $set[3][0], "\n";
}

// preg_replace with multiple subjects
$out = preg_replace('/\d+/', 'X', ["a1", "b22", "c333"]);
print_r($out);

$out = preg_replace(['/a/', '/b/'], ['1', '2'], "abc");
echo $out, "\n";

// preg_replace_callback_array
$r = preg_replace_callback_array([
    '/\d+/' => fn($m) => "<num:$m[0]>",
    '/[a-z]+/' => fn($m) => strtoupper($m[0]),
], "abc 123 def");
echo $r, "\n";

// preg_match named groups
preg_match('/(?<year>\d{4})-(?<month>\d{2})/', "Date 2024-06", $m);
echo $m['year'], "/", $m['month'], "\n";
echo $m[1], "/", $m[2], "\n";

// preg with unicode
preg_match_all('/\p{L}+/u', "Hello, мир! 你好", $m);
print_r($m[0]);

// dynamic property access ?-> chain
class A { public ?B $b = null; }
class B { public ?C $c = null; }
class C { public string $v = "deep"; }

$a = new A;
$a->b = new B;
$a->b->c = new C;
echo $a->b?->c?->v, "\n";
echo $a->b?->c?->v ?? "null", "\n";

$a2 = new A;
echo $a2->b?->c?->v ?? "null", "\n"; // null
echo $a2->b?->c?->v, "|\n"; // empty

// array access nullable
$arr = null;
echo $arr["key"] ?? "u", "\n"; // u

// match with array values
$result = match([1, 2]) {
    [1, 2] => "matched",
    default => "no",
};
echo $result, "\n"; // PHP 8 doesn't strict-equal arrays for match? actually it does

$arr = [3, 4];
$result = match($arr) {
    [1, 2] => "ab",
    [3, 4] => "cd",
    default => "no",
};
echo $result, "\n";

// array_map with strings
print_r(array_map('strtoupper', ['a', 'b', 'c']));
print_r(array_map('intval', ['1', '2x', 'abc']));

// closures over closures
$add = fn($x) => fn($y) => $x + $y;
$add5 = $add(5);
echo $add5(3), ":", $add5(10), "\n";

// generator inside generator
function multi() {
    for ($i = 0; $i < 3; $i++) {
        yield from range($i*10, $i*10+2);
    }
}
foreach (multi() as $v) echo "$v ";
echo "\n";

// strrev unicode (byte)
echo strrev("héllo"), "\n"; // mangled multi-byte

// mb_strlen / strlen
echo strlen("héllo"), ":", mb_strlen("héllo"), "\n"; // 6:5

// mb_substr
echo mb_substr("héllo", 0, 3), "\n";
echo mb_substr("héllo", -2), "\n";

// str_pad with multibyte
echo str_pad("abc", 10, "-", STR_PAD_BOTH), "|\n";
echo str_pad("héllo", 10, "x"), "|\n"; // byte-padding gives 10 bytes, not 10 chars

// number_format strict
echo number_format(1234.5, 2, ",", "."), "\n";
echo number_format(0, 2), "\n";
echo number_format(-1.5), "\n";

// sprintf %% literal
echo sprintf("100%%"), "\n";
echo sprintf("%d%%", 50), "\n";

// int overflow
$x = PHP_INT_MAX;
$y = $x + 1;
echo gettype($y), "\n"; // float (overflow)
$y = $x * 2;
echo gettype($y), "\n";
