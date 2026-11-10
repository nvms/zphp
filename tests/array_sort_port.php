<?php
// the sort family follows php's zend_sort, comparison functions and flags
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
$names = ["img12.png", "img10.png", "IMG2.png", "img1.png", "Img3.png", "a01", "A1", "a1", " a2", "0001", "1", "01", "0.5", "00", "0", "-1", "0-0"];
$a = $names; natsort($a); var_dump($a);
$a = $names; natcasesort($a); var_dump($a);
$a = $names; sort($a, SORT_NATURAL | SORT_FLAG_CASE); var_dump($a);
$a = $names; rsort($a, SORT_STRING | SORT_FLAG_CASE); var_dump($a);
$a = $names; asort($a, SORT_NUMERIC); var_dump($a);
$a = array_flip($names); ksort($a, SORT_NATURAL); var_dump(array_keys($a));
$a = array_flip($names); krsort($a, SORT_NATURAL | SORT_FLAG_CASE); var_dump(array_keys($a));
$a = array_flip($names); krsort($a, SORT_STRING); var_dump(array_keys($a));
$a = array_flip($names); ksort($a, SORT_NUMERIC); var_dump(array_keys($a));

// natsort reads references and converts ints and floats
$x = 100; $y = 33; $z = 555;
$r = [&$x, &$y, &$z];
natsort($r); var_dump($r);
$n = [12345, -2345, 0, 1, 10.5, -10.5, 0.5];
natcasesort($n); var_dump($n);

// stringable objects
class S { function __construct(public $v) {} function __toString(): string { return $this->v; } }
$o = [new S("b10"), new S("B2"), new S("a")];
natcasesort($o); foreach ($o as $k => $v) echo "$k=$v\n";

// SORT_STRING warns for arrays
$m = [[1], "b", "a"];
sort($m, SORT_STRING); var_dump($m);

// numeric sort with objects warns
class P {}
$p = [new P, 2, 1];
sort($p, SORT_NUMERIC); var_dump(count($p));

// bool comparison results are deprecated, once per call
$u = [3, 1, 2];
usort($u, fn($a, $b) => $a > $b); var_dump($u);
uasort($u, fn($a, $b) => $a < $b); var_dump($u);
uksort($u, fn($a, $b) => $a > $b); var_dump($u);

// the comparisons a callback sees follow zend_sort
$calls = [];
$big = range(1, 20); shuffle($big); $big = [17, 3, 9, 1, 20, 12, 5, 14, 8, 2, 19, 6, 11, 16, 4, 10, 13, 7, 18, 15];
usort($big, function ($a, $b) use (&$calls) { $calls[] = "$a:$b"; return $a <=> $b; });
echo implode(",", $calls), "\n";

// multisort flags
$data = ["Second", "First", "Tenth", "Twentieth", "Third"];
$ids = [2, 1, 10, 20, 3];
array_multisort($data, SORT_NATURAL, $ids); var_dump($data, $ids);
$k = ["b" => 2, 9 => 1, "a" => 3];
array_multisort($k); var_dump($k); $k[] = "next"; var_dump($k);
foreach ([[1, SORT_ASC, SORT_DESC], [[1], SORT_STRING, SORT_NUMERIC], [0], [12345], [1.5], [[1], [1, 2]]] as $args) {
    try {
        var_dump(array_multisort(...$args));
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
$c = ["c", "a", "b"]; $d = [1, 2, 3];
array_multisort($c, SORT_DESC, SORT_STRING, $d, SORT_ASC); var_dump($c, $d);
