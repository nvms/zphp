<?php
echo isset($undef) ? "y" : "n", "\n";
$x = null;
echo isset($x) ? "y" : "n", "\n";
$x = 0;
echo isset($x) ? "y" : "n", "\n";
$x = "";
echo isset($x) ? "y" : "n", "\n";
$x = false;
echo isset($x) ? "y" : "n", "\n";

$arr = ["a" => 1, "b" => null];
echo isset($arr["a"]) ? "y" : "n", "\n";
echo isset($arr["b"]) ? "y" : "n", "\n";
echo isset($arr["nope"]) ? "y" : "n", "\n";

$obj = new stdClass;
$obj->a = 1;
$obj->b = null;
echo isset($obj->a) ? "y" : "n", "\n";
echo isset($obj->b) ? "y" : "n", "\n";
echo isset($obj->nope) ? "y" : "n", "\n";

echo isset($undef, $arr) ? "y" : "n", "\n";
echo isset($arr, $obj) ? "y" : "n", "\n";

echo empty($undef) ? "y" : "n", "\n";
echo empty(0) ? "y" : "n", "\n";
echo empty(0.0) ? "y" : "n", "\n";
echo empty("0") ? "y" : "n", "\n";
echo empty("") ? "y" : "n", "\n";
echo empty(null) ? "y" : "n", "\n";
echo empty(false) ? "y" : "n", "\n";
echo empty([]) ? "y" : "n", "\n";
echo empty("00") ? "y" : "n", "\n";
echo empty(1) ? "y" : "n", "\n";
echo empty("a") ? "y" : "n", "\n";
echo empty([0]) ? "y" : "n", "\n";

$arr = ["x" => 0];
echo empty($arr["x"]) ? "y" : "n", "\n";
echo empty($arr["nope"]) ? "y" : "n", "\n";

echo 1 === 1 ? "y" : "n", "\n";
echo 1 === "1" ? "y" : "n", "\n";
echo 1 === 1.0 ? "y" : "n", "\n";
echo null === null ? "y" : "n", "\n";
echo null === false ? "y" : "n", "\n";
echo [] === [] ? "y" : "n", "\n";
echo [1, 2] === [1, 2] ? "y" : "n", "\n";
echo [1, 2] === [2, 1] ? "y" : "n", "\n";
echo ["a"=>1, "b"=>2] === ["a"=>1, "b"=>2] ? "y" : "n", "\n";
echo ["a"=>1, "b"=>2] === ["b"=>2, "a"=>1] ? "y" : "n", "\n";

echo true ? "y" : "n", "\n";
echo false ? "y" : "n", "\n";
echo 1 ?: "alt", "\n";
echo 0 ?: "alt", "\n";
echo null ?? "default", "\n";
echo 0 ?? "default", "\n";
echo "" ?? "default", "\n";

$arr = ["k" => 1];
echo $arr["k"] ?? "default", "\n";
echo $arr["missing"] ?? "default", "\n";

$x = null;
echo $x ?? "default", "\n";
$x = 0;
echo $x ?? "default", "\n";

$obj = null;
echo $obj?->prop ?? "null", "\n";

$obj = new stdClass;
$obj->prop = "hello";
echo $obj?->prop ?? "null", "\n";

class Wrap {
    public ?Wrap $inner = null;
    public string $val = "leaf";
}
$w = new Wrap;
echo $w?->inner?->inner?->val ?? "null", "\n";

$w->inner = new Wrap;
$w->inner->inner = new Wrap;
echo $w?->inner?->inner?->val ?? "null", "\n";

$x = 5;
$y = 10;
echo $x < $y ? "lt" : "gte", "\n";
echo $x > $y ? "gt" : "lte", "\n";
echo $x === $y - 5 ? "eq" : "ne", "\n";

echo (5 > 3) && (3 > 1) ? "y" : "n", "\n";
echo (5 > 3) || (1 > 3) ? "y" : "n", "\n";
echo !(5 > 3) ? "y" : "n", "\n";

echo (true xor false) ? "y" : "n", "\n";
echo (true xor true) ? "y" : "n", "\n";

echo true && false ? "y" : "n", "\n";
echo true || false ? "y" : "n", "\n";
echo true and false ? "y" : "n", "\n";
echo true or false ? "y" : "n", "\n";

$a = 5;
$b = 10;
$max = $a > $b ? $a : $b;
echo $max, "\n";

$value = $arr["k"] ?? null;
echo $value, "\n";

$arr["k"] = null;
$value = $arr["k"] ?? null;
echo var_export($value, true), "\n";

echo (10 - 5) * 2, "\n";
echo 10 - (5 * 2), "\n";

echo 10 % 3, "\n";
echo -10 % 3, "\n";

echo (5 <=> 3), "\n";
echo (3 <=> 5), "\n";
echo (5 <=> 5), "\n";

$nullsafe = null;
echo isset($nullsafe?->prop) ? "y" : "n", "\n";

echo isset($undef) || isset($arr) ? "y" : "n", "\n";
echo isset($arr) && isset($obj) ? "y" : "n", "\n";

$cnt = 0;
$cnt = ($cnt ?? 0) + 1;
echo $cnt, "\n";

$x = null;
$x ??= "default";
echo $x, "\n";
$x ??= "second";
echo $x, "\n";

$arr = [];
$arr["k"] ??= "v";
$arr["k"] ??= "v2";
print_r($arr);

$nested = ["a" => ["b" => null]];
$nested["a"]["b"] ??= "filled";
echo $nested["a"]["b"], "\n";

echo isset($foo) ? "y" : "n", "\n";
$foo = "bar";
echo isset($foo) ? "y" : "n", "\n";
$foo = null;
echo isset($foo) ? "y" : "n", "\n";
