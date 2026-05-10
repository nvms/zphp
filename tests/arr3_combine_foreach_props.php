<?php
// array_diff_ukey
$cmp = fn($a, $b) => strcmp((string)$a, (string)$b);
print_r(array_diff_ukey(["a"=>1,"b"=>2,"c"=>3], ["a"=>9,"d"=>4], $cmp));

// array_intersect_uassoc
$cmp = fn($a, $b) => strcmp((string)$a, (string)$b);
print_r(array_intersect_uassoc(["a"=>1,"b"=>2,"c"=>3], ["a"=>1,"b"=>9,"d"=>3], $cmp));

// array_intersect_ukey
print_r(array_intersect_ukey(["a"=>1,"b"=>2,"c"=>3], ["a"=>9,"b"=>0], $cmp));

// usort with throwing callback - PHP rethrows
try {
    $arr = [3, 1, 2];
    usort($arr, function ($a, $b) {
        if ($b === 1) throw new RuntimeException("from cmp");
        return $a <=> $b;
    });
    echo "no err\n";
} catch (\RuntimeException $e) {
    echo "caught:", $e->getMessage(), "\n";
}

// ksort/asort on int-keyed array
$arr = [3 => "c", 1 => "a", 2 => "b"];
$copy = $arr;
ksort($copy);
print_r($copy);

$copy = $arr;
asort($copy); // sort by value preserve keys
print_r($copy);

// foreach over object's public props
class O {
    public int $a = 1;
    public string $b = "x";
    private int $hidden = 99;
    public array $c = [1, 2];
}
foreach (new O as $k => $v) echo "$k=", is_array($v) ? "[arr]" : $v, "|";
echo "\n";

// foreach by ref over generator: PHP errors, zphp doesn't (architectural)

// array_combine with NULL values
print_r(array_combine(["a", "b"], [null, null]));
print_r(array_combine(["a", "b", "c"], [1, null, "x"]));

// length mismatch
try {
    array_combine(["a", "b"], [1, 2, 3]);
    echo "no err\n";
} catch (\ValueError $e) {
    echo "ve:", $e->getMessage(), "\n";
}

// empty arrays
print_r(array_combine([], []));

// array_combine with object keys
try {
    array_combine([new stdClass], [1]);
    echo "no err\n";
} catch (\Throwable $e) {
    echo "te\n";
}

// ksort with SORT flags
$arr = ["10" => "a", "2" => "b", "1" => "c"];
$copy = $arr;
ksort($copy, SORT_STRING);
foreach ($copy as $k => $v) echo "$k:$v ";
echo "\n";
$copy = $arr;
ksort($copy, SORT_NUMERIC);
foreach ($copy as $k => $v) echo "$k:$v ";
echo "\n";
$copy = $arr;
ksort($copy, SORT_NATURAL);
foreach ($copy as $k => $v) echo "$k:$v ";
echo "\n";

// natsort
$arr = ["img12.png", "img10.png", "img2.png", "img1.png"];
natsort($arr);
foreach ($arr as $v) echo "$v ";
echo "\n";

// array_slice with positive/negative offset
$arr = [10, 20, 30, 40, 50];
print_r(array_slice($arr, 1, 3));
print_r(array_slice($arr, -2));
print_r(array_slice($arr, 0, -2));
print_r(array_slice($arr, -3, -1));

// array_splice
$arr = [1, 2, 3, 4, 5];
$removed = array_splice($arr, 1, 2, ["x", "y", "z"]);
print_r($removed);
print_r($arr);

$arr = [1, 2, 3];
array_splice($arr, 0, 0, [0, "a"]);
print_r($arr);

// array_reverse with preserve_keys
print_r(array_reverse([1, 2, 3]));
print_r(array_reverse([1, 2, 3], true));
print_r(array_reverse(["a" => 1, "b" => 2, "c" => 3]));

// array_filter with strict-ish
print_r(array_filter([0, 1, 2, false, "", null, "0", 3]));
print_r(array_filter(["a", "", "b", 0, null], fn($v) => $v !== null));
