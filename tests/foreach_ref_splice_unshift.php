<?php
// a by-reference foreach keeps its place the way php's hash iterators do
// when array_unshift or array_splice rebuild the array under it

function run(string $label, array $a, int $at, callable $change): void
{
    echo "$label:";
    $done = false;
    $n = 0;
    foreach ($a as &$v) {
        echo " ", is_array($v) ? 'array' : $v;
        if (!$done && $n === $at) {
            $done = true;
            $change($a);
        }
        if (++$n > 40) {
            echo " (runaway)";
            break;
        }
    }
    unset($v);
    echo " | ", implode(",", $a), "\n";
}

run("unshift", [1, 2, 3], 1, function (&$a) { array_unshift($a, 0, 0, 0); });
run("unshift at start", [1, 2, 3], 0, function (&$a) { array_unshift($a, 'a'); });
run("unshift at end", [1, 2, 3], 2, function (&$a) { array_unshift($a, 'a', 'b'); });
run("remove before", [0, 1, 2, 3, 4], 3, function (&$a) { array_splice($a, 1, 2); });
run("remove after", [0, 1, 2, 3, 4], 0, function (&$a) { array_splice($a, 2, 2); });
run("remove current", [0, 1, 2, 3, 4], 2, function (&$a) { array_splice($a, 1, 3); });
run("remove to end", [0, 1, 2, 3, 4], 2, function (&$a) { array_splice($a, 1); });
run("replace before", [0, 1, 2, 3, 4], 3, function (&$a) { array_splice($a, 1, 2, ['x', 'y', 'z']); });
run("replace after", [0, 1, 2, 3, 4], 0, function (&$a) { array_splice($a, 2, 2, ['x', 'y', 'z']); });
run("replace current", [0, 1, 2, 3, 4], 1, function (&$a) { array_splice($a, 1, 3, ['x', 'y', 'z']); });
run("grow in front", [0, 1, 2, 3, 4, 5, 6], 2, function (&$a) { array_splice($a, 0, 0, ['x']); });
run("grow by two", [0, 1, 2, 3, 4, 5, 6], 1, function (&$a) { array_splice($a, 0, 1, ['x', 'y', 'z']); });
run("shrink", [0, 1, 2, 3, 4, 5, 6], 4, function (&$a) { array_splice($a, 0, 3, ['x']); });
run("insert only", [0, 1, 2, 3], 1, function (&$a) { array_splice($a, 2, 0, ['x', 'y']); });
