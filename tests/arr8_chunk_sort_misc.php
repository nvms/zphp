<?php
// array_chunk(0) ValueError
try { array_chunk([1,2,3], 0); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
try { array_chunk([1,2,3], -1); echo "no\n"; } catch (\ValueError $e) { echo "ve-neg\n"; }

// chunk size larger than array
print_r(array_chunk([1,2], 5));
print_r(array_chunk([], 2));

// chunk preserve_keys
print_r(array_chunk(["a"=>1, "b"=>2, "c"=>3, "d"=>4], 2, true));

// array_combine empty
print_r(array_combine([], []));

// range with float step precision
print_r(range(0.0, 1.0, 0.25));
print_r(range(0.0, 1.0, 0.1)); // float precision quirks

print_r(range(1, 10));
print_r(range(10, 1, -1));
print_r(range(10, 1, 1)); // PHP allows or auto-flips? auto-flips for ints with step 1
print_r(range('a', 'e'));
print_r(range('a', 'A')); // descending

// range float comparisons
print_r(range(0.0, 0.5, 0.1));

// sort with callable returning floats
$arr = [3.5, 1.2, 2.8];
usort($arr, fn($a, $b) => $a - $b); // float diff (PHP coerces to int)
print_r($arr);

usort($arr, fn($a, $b) => $a <=> $b); // proper spaceship
print_r($arr);

// sort stability (PHP 8+ uses stable sort)
$arr = [
    ["g" => 1, "id" => "a"],
    ["g" => 2, "id" => "b"],
    ["g" => 1, "id" => "c"],
    ["g" => 2, "id" => "d"],
];
usort($arr, fn($x, $y) => $x["g"] <=> $y["g"]);
foreach ($arr as $e) echo $e["id"];
echo "\n"; // acbd (stable)

uasort($arr, fn($x, $y) => $x["g"] <=> $y["g"]);
foreach ($arr as $k => $e) echo $e["id"];
echo "\n";

// sort with mixed types
$arr = [3, "1", 2, "10", 1.5];
sort($arr);
print_r($arr);

// usort returning 0 (equal)
$arr = ["b", "a", "c"];
usort($arr, fn($a, $b) => 0); // all equal, stable original order
print_r($arr);

// sort with closure throwing
try {
    $arr = [3, 1, 2];
    usort($arr, function ($a, $b) {
        if ($b === 1) throw new RuntimeException("at $b");
        return $a <=> $b;
    });
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "caught:", $e->getMessage(), "\n";
}

// sort empty array
$arr = [];
sort($arr);
var_dump($arr);
echo count($arr), "\n";

// max with array
echo max([1, 2, 3]), "\n";
echo max([5]), "\n";
try { max([]); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

// min with array
echo min([3, 1, 2]), "\n";

// array_sum on mixed
// array_sum with non-numeric strings: PHP emits warning (architectural)
echo array_sum([1, 2, "3", "4"]), "\n"; // 10
echo array_sum([1, "1.5"]), "\n"; // 2.5

// array_product
echo array_product([2, 3, 4]), "\n"; // 24
echo array_product([]), "\n"; // 1
echo array_product([0, 100]), "\n"; // 0

// closure in usort
class Sorter {
    public function __invoke($a, $b): int { return $b <=> $a; }
}
$arr = [3, 1, 2];
usort($arr, new Sorter);
print_r($arr); // descending

// uasort preserving keys
$arr = ["x"=>3, "y"=>1, "z"=>2];
uasort($arr, fn($a, $b) => $a <=> $b);
foreach ($arr as $k => $v) echo "$k=$v ";
echo "\n";

// uksort
$arr = ["zebra"=>1, "apple"=>2, "mango"=>3];
uksort($arr, fn($a, $b) => strcmp($a, $b));
foreach ($arr as $k => $v) echo "$k=$v ";
echo "\n";
