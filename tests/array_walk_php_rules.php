<?php
// array_walk follows php_array_walk: the element is a reference, the key and
// user data are values (a by-reference parameter for them warns), removed
// elements are skipped, objects walk their property table, nested arrays
// shared with another copy are separated, and too few parameters throw
$a = [1, 2, 3];
array_walk($a, function (&$v, $k, &$data) { $v *= 10; $data[] = $k; }, $collected);
var_dump($a, $collected ?? null);

$a = array_fill(0, 10, 1);
array_walk($a, function ($v, $k) use (&$a) {
    echo $k, " ";
    unset($a[$k], $a[$k + 1], $a[$k + 2]);
});
echo "\n";
var_dump($a);

$a = [1, 2];
array_walk($a, function ($v, $k) use (&$a) {
    if ($k === 0) $a["x"] = 3;
    echo $k, "=", $v, " ";
});
echo "\n";

$a = ["a" => 1, "b" => 2];
array_walk($a, function ($v, $k) use (&$a) { $a[$k] = $v + 100; });
var_dump($a);

class C {
    public $pub = 1;
    protected $pro = 2;
    private $pri = 3;
}
$o = new C;
array_walk($o, function (&$v, $k) { var_dump($k); $v = $v * 2; });
var_dump($o);

$data = ["k" => "v", ["n" => "w"]];
function change(&$v, $k) { $v = "changed"; }
function walkCopy($d) {
    array_walk_recursive($d, "change");
    return $d;
}
var_dump(walkCopy($data), $data);

function three($a, $b, $c) { echo "called\n"; }
foreach ([fn() => array_walk($data, "three"), fn() => array_walk_recursive($data, "three"), fn() => array_walk($o, function (&$v, $k, $x) {})] as $f) {
    try {
        $f();
    } catch (ArgumentCountError $e) {
        echo $e->getMessage(), "\n";
    }
}
foreach ([fn() => array_walk($s, "change"), fn() => array_walk_recursive($s, "change")] as $f) {
    $s = "str";
    try {
        $f();
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
