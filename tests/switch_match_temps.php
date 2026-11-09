<?php
function f($a) {
    switch ($a) { case 1: $x = 2; var_dump(get_defined_vars()); break; }
    $r = match ($a) { 1 => compact('x'), default => [] };
    var_dump($r);
    extract(['y' => 5]);
    switch ($y) { case 5: echo "five\n"; }
    $n = 'y'; echo $$n, "\n";
}
f(1);
function g($x) {
    return match (true) { $x < match ($x % 2) { 0 => 5, 1 => 7 } => "small", default => "big" };
}
function h($v) {
    switch ($v) { case match ($v) { 1 => 1, default => 0 }: return "one"; case 2: switch ($v + 1) { case 3: return "nested"; } }
    return "none";
}
echo g(4), g(6), g(9), h(1), h(2), h(3), "\n";
