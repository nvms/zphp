<?php
// SplFixedArray::fromArray
$fa = SplFixedArray::fromArray([10, 20, 30]);
echo $fa->getSize(), ":", $fa[0], ",", $fa[1], ",", $fa[2], "\n";

// fromArray with assoc keys (PHP throws InvalidArgumentException)
try {
    $fa = SplFixedArray::fromArray(["a" => 1, "b" => 2]);
    echo "got-size:", $fa->getSize(), "\n";
} catch (\Throwable $e) { echo "err:", get_class($e), "\n"; }

// fromArray preserve_keys=true with numeric only
$fa = SplFixedArray::fromArray([0 => "a", 1 => "b", 5 => "z"], true);
echo $fa->getSize(), ":", var_export($fa[5] ?? null, true), "\n";

// ArrayObject sort methods
$ao = new ArrayObject(["b" => 3, "a" => 1, "c" => 2]);
$ao->ksort();
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";
$ao->asort();
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";

$ao = new ArrayObject([3, 1, 4, 1, 5, 9, 2, 6]);
$ao->uasort(fn($a, $b) => $a <=> $b);
foreach ($ao as $v) echo "$v ";
echo "\n";

// uksort weird returns (still valid, sign matters)
$arr = ["x" => 1, "a" => 2, "m" => 3];
uksort($arr, fn($a, $b) => $a <=> $b);
print_r($arr);

uksort($arr, fn($a, $b) => 0); // all equal - stable
print_r($arr);

// uksort with non-numeric returns (PHP coerces)
$arr = [3, 1, 2];
usort($arr, fn($a, $b) => "non-numeric"); // 0 (becomes 0)
print_r($arr);

// exception in array_map callback
try {
    $r = array_map(function ($x) {
        if ($x === 2) throw new RuntimeException("at $x");
        return $x * 10;
    }, [1, 2, 3]);
    echo "no err\n";
} catch (\RuntimeException $e) {
    echo "caught:", $e->getMessage(), "\n";
}

// sleep returns
$r = sleep(0);
var_dump($r);

// time() returns
$t = time();
echo gettype($t), ":", $t > 0 ? "pos" : "neg", "\n";

// date_default_timezone_get
$tz = date_default_timezone_get();
echo gettype($tz), ":", strlen($tz) > 0 ? "set" : "unset", "\n";

date_default_timezone_set("UTC");
echo date_default_timezone_get(), "\n";

date_default_timezone_set("America/New_York");
echo date_default_timezone_get(), "\n";

// strtotime with timezone
echo date("Y-m-d H:i:s", strtotime("2024-06-15 12:00:00 UTC")), "\n";
echo date("Y-m-d H:i:s", strtotime("2024-06-15 12:00:00 +0500")), "\n";

date_default_timezone_set("UTC");
$t = strtotime("2024-06-15 12:00:00");
echo date("Y-m-d H:i:s", $t), "\n";

// explode with -1 limit
print_r(explode(",", "a,b,c,d,e", -1)); // drops last
print_r(explode(",", "a,b,c,d,e", -2)); // drops last 2
print_r(explode(",", "a,b,c", -10)); // empty

// explode with 0 limit (treated as 1)
print_r(explode(",", "a,b,c", 0)); // ["a,b,c"]

// explode with positive limit
print_r(explode(",", "a,b,c,d", 2));
print_r(explode(",", "a,b,c,d", 100));
print_r(explode(",", "")); // [""]
print_r(explode(",", "abc")); // ["abc"]

// implode reverse
echo implode("-", ["a", "b", "c"]), "\n";
echo implode([1,2,3]), "\n"; // 1-arg form: glue defaults to ""
echo join("|", ["x", "y"]), "\n";

// preg_grep
print_r(preg_grep('/^\d+$/', ["abc", "123", "x4", "456"]));
print_r(preg_grep('/^\d+$/', ["abc", "123", "x4", "456"], PREG_GREP_INVERT));

// asort vs ksort numeric vs string
$arr = ["b" => "banana", "a" => "apple", "c" => "cherry"];
$copy = $arr;
asort($copy);
print_r($copy);
$copy = $arr;
ksort($copy);
print_r($copy);
$copy = $arr;
arsort($copy);
print_r($copy);
$copy = $arr;
krsort($copy);
print_r($copy);
