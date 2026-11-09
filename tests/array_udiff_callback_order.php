<?php
// the callback variants sort a copy of every array with php's hybrid
// insertion/quick sort and walk the copies together, so which pairs a
// comparison callback sees, and in what order, is part of the behavior

error_reporting(E_ALL);

function logged(string $tag): Closure
{
    return function ($a, $b) use ($tag) {
        echo $tag, '(', is_array($a) ? 'arr' : var_export($a, true), ',', is_array($b) ? 'arr' : var_export($b, true), ') ';
        return $a <=> $b;
    };
}

$v = logged('v');
$k = logged('k');
$colors1 = ['a' => 'green', 'b' => 'brown', 'c' => 'blue', 'red'];
$colors2 = ['a' => 'GREEN', 'B' => 'brown', 'yellow', 'red'];
$colors3 = ['red', 'a' => 'green', 'blue'];

foreach (['array_udiff', 'array_uintersect', 'array_udiff_assoc', 'array_uintersect_assoc'] as $fn) {
    echo "$fn:\n";
    $r = $fn($colors1, $colors2, $colors3, $v);
    echo "\n", json_encode($r), "\n";
}
foreach (['array_diff_ukey', 'array_intersect_ukey', 'array_diff_uassoc', 'array_intersect_uassoc'] as $fn) {
    echo "$fn:\n";
    $r = $fn($colors1, $colors2, $colors3, $k);
    echo "\n", json_encode($r), "\n";
}
foreach (['array_udiff_uassoc', 'array_uintersect_uassoc'] as $fn) {
    echo "$fn:\n";
    $r = $fn($colors1, $colors2, $colors3, $v, $k);
    echo "\n", json_encode($r), "\n";
}

echo "-- past sixteen elements the sort partitions --\n";
$scores = [];
$seen = [];
for ($i = 0; $i < 40; $i++) {
    $scores["player$i"] = ($i * 37) % 23;
    $seen[($i * 11) % 31] = ($i * 7) % 19;
}
$calls = 0;
$counting = function ($a, $b) use (&$calls) {
    $calls++;
    return $a <=> $b;
};
foreach (['array_udiff', 'array_uintersect', 'array_diff_ukey', 'array_intersect_uassoc', 'array_udiff_uassoc'] as $fn) {
    $calls = 0;
    $args = [$scores, $seen, $counting];
    if ($fn === 'array_udiff_uassoc') $args[] = $counting;
    $r = $fn(...$args);
    echo "$fn: $calls calls, ", json_encode($r), "\n";
}

echo "-- comparisons that disagree with themselves --\n";
$coin = function ($a, $b) {
    echo crc32("$a|$b") % 3 - 1, ' ';
    return crc32("$a|$b") % 3 - 1;
};
var_dump(array_udiff(range(1, 20), range(5, 25), $coin));
var_dump(array_uintersect(range(1, 20), range(5, 25), $coin));

echo "-- returning a bool is deprecated, and false asks again swapped --\n";
$greater = function ($a, $b) {
    echo "[$a $b] ";
    return $a > $b;
};
var_dump(array_udiff([3, 1, 2], [2, 4], $greater));
var_dump(array_diff_ukey(['b' => 1, 'a' => 2], ['a' => 0], $greater));
echo "-- the plain-value callback of the _assoc variants takes ints as given --\n";
var_dump(array_udiff_assoc(['x' => 1, 'y' => 2], ['x' => 1, 'y' => 3], fn($a, $b) => $a == $b ? false : true));

echo "-- a callback that throws stops the walk --\n";
try {
    array_uintersect([1, 2, 3, 4], [3, 4, 5], function ($a, $b) {
        echo "($a,$b) ";
        if ($a === 4 || $b === 4) throw new RuntimeException("stop at four");
        return $a <=> $b;
    });
} catch (RuntimeException $e) {
    echo "\ncaught: ", $e->getMessage(), "\n";
}
