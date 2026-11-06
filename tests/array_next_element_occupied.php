<?php
// appending to an array whose next index would pass PHP_INT_MAX is an Error
// wherever php raises it, and leaves the array as it was elsewhere
$full = [PHP_INT_MAX => 1];
foreach ([
    'assign' => function () use ($full) { $a = $full; $a[] = 2; },
    'nested' => function () use ($full) { $a = $full; $a[][] = 2; },
    'literal' => function () { $a = [PHP_INT_MAX => 1, 2]; },
    'spread' => function () use ($full) { $a = [...$full, ...[1]]; },
    'array_push' => function () use ($full) { $a = $full; array_push($a, 2); },
    'array_fill' => function () { array_fill(PHP_INT_MAX, 2, 0); },
    'array_fill1' => function () { var_dump(count(array_fill(PHP_INT_MAX, 1, 0))); },
    'ref' => function () use ($full) { $a = $full; $x = 1; $a[] = &$x; },
    'list' => function () use ($full) { $a = $full; [$a[]] = [1]; },
    'merge_recursive' => function () { var_dump(array_merge_recursive([PHP_INT_MAX => 1], [2])); },
    'array_pad' => function () { var_dump(count(array_pad([PHP_INT_MAX => 1], 3, 0))); },
    'unshift' => function () { $a = [PHP_INT_MAX => 1]; array_unshift($a, 0); var_dump(array_keys($a)); },
    'splice' => function () { $a = [PHP_INT_MAX => 1]; array_splice($a, 0, 0, [9]); var_dump($a); },
    'iterator_to_array' => function () { var_dump(iterator_to_array((function () { yield PHP_INT_MAX => 1; yield 2; })(), true)); },
] as $name => $f) {
    try { $f(); echo "$name: no error\n"; } catch (Throwable $e) { echo "$name: ", get_class($e), ": ", $e->getMessage(), "\n"; }
}
var_dump(array_merge_recursive([5 => 1, 'a' => [1], 'b' => 2, 'n' => null], [2, 'a' => [3, 'k' => 4], 'b' => [5], 'n' => 1, 'c' => 'x'], ['b' => 'y', 'a' => ['k' => 6]]));
var_dump(array_merge_recursive(['a' => 1], ['a' => (object)['p' => 1]]));
var_dump(array_merge_recursive([3 => 'x']));
try { array_merge_recursive([1], 2); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { var_dump(array_merge_recursive(['a' => [PHP_INT_MAX => 1]], ['a' => 2])); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { var_dump([PHP_INT_MAX - 1 => 0, ...[1, 2, 3]]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { var_dump([PHP_INT_MAX - 1 => 0, ...(function () { yield 1; yield 2; })()]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { array_fill(0, -1, 0); } catch (ValueError $e) { echo $e->getMessage(), "\n"; }
var_dump(array_fill(PHP_INT_MAX - 1, 2, 'x'));
