<?php

// foreach ref inside function with nested array modification
function modifyNested(&$data) {
    foreach ($data as &$item) {
        $item *= 2;
    }
    unset($item);
}

$nums = [1, 2, 3, 4];
modifyNested($nums);
echo "foreach ref in func: " . implode(", ", $nums) . "\n";

// list() destructuring from method return
class Pair {
    public static function get(): array {
        return [42, "hello"];
    }
    public function values(): array {
        return [10, 20, 30];
    }
}

[$a, $b] = Pair::get();
echo "list from static: a=$a, b=$b\n";

$p = new Pair();
[$x, $y, $z] = $p->values();
echo "list from method: x=$x, y=$y, z=$z\n";

// list with skipped elements
[, $second, , $fourth] = [10, 20, 30, 40];
echo "list skip: second=$second, fourth=$fourth\n";

// nested list
[[$a, $b], [$c, $d]] = [[1, 2], [3, 4]];
echo "nested list: a=$a, b=$b, c=$c, d=$d\n";

// negative array indices
$arr = [10, 20, 30];
echo "negative slice: " . $arr[count($arr) - 1] . "\n";
$arr2 = ["a" => 1, "b" => 2, "c" => 3];
echo "array_values: " . array_values($arr2)[0] . "\n";

// compact and extract
function testCompactExtract() {
    $name = "Alice";
    $age = 30;
    $data = compact("name", "age");
    echo "compact: name=" . $data["name"] . ", age=" . $data["age"] . "\n";

    $info = ["color" => "blue", "size" => "large"];
    extract($info);
    echo "extract: color=$color, size=$size\n";
}
testCompactExtract();

// string offset read
$str = "Hello";
echo "str[0]: " . $str[0] . "\n";
echo "str[4]: " . $str[4] . "\n";
echo "str[-1]: " . $str[strlen($str) - 1] . "\n";

// array_walk with reference
$prices = [10.0, 20.0, 30.0];
array_walk($prices, function(&$price, $key) {
    $price *= 1.1;
});
echo "array_walk ref: " . round($prices[0], 1) . ", " . round($prices[1], 1) . ", " . round($prices[2], 1) . "\n";

// chained array operations
$data = [3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5];
$unique = array_unique($data);
sort($unique);
echo "unique sorted: " . implode(", ", $unique) . "\n";

// array_splice
$arr = ["a", "b", "c", "d", "e"];
$removed = array_splice($arr, 1, 2, ["x", "y", "z"]);
echo "splice result: " . implode(", ", $arr) . "\n";
echo "splice removed: " . implode(", ", $removed) . "\n";

// in_array strict
echo "in_array loose: " . (in_array("1", [1, 2, 3]) ? "true" : "false") . "\n";
echo "in_array strict: " . (in_array("1", [1, 2, 3], true) ? "true" : "false") . "\n";

// array_key_exists vs isset
$arr = ["key" => null, "other" => 0];
echo "key_exists null: " . (array_key_exists("key", $arr) ? "true" : "false") . "\n";
echo "isset null: " . (isset($arr["key"]) ? "true" : "false") . "\n";
echo "isset zero: " . (isset($arr["other"]) ? "true" : "false") . "\n";

// multiple assignment
$a = $b = $c = 42;
echo "multi assign: a=$a, b=$b, c=$c\n";

// ternary and null coalesce chains
$val = null ?? false ?: "default";
echo "null coalesce chain: $val\n";

// array_map with keys
$arr = ["a" => 1, "b" => 2, "c" => 3];
$result = array_map(function($v) { return $v * 10; }, $arr);
echo "map keys preserved: " . ($result["a"] === 10 && $result["b"] === 20 ? "true" : "false") . "\n";

// array_filter preserves keys
$arr = [1, 2, 3, 4, 5, 6];
$even = array_filter($arr, function($v) { return $v % 2 === 0; });
echo "filter keys: " . implode(",", array_keys($even)) . "\n";

// type juggling in comparisons
echo "0 == false: " . (0 == false ? "true" : "false") . "\n";
echo "'' == false: " . ('' == false ? "true" : "false") . "\n";
echo "0 == '': " . (0 == '' ? "true" : "false") . "\n";
echo "'0' == false: " . ('0' == false ? "true" : "false") . "\n";
echo "null == false: " . (null == false ? "true" : "false") . "\n";
