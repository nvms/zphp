<?php
// by-reference destructuring: missing elements are made, a call's result
// that isn't a reference hands out copies, array elements and ArrayAccess
// objects as targets and sources
$arr = [1, [2]];
[&$a, [&$b], &$c] = $arr;
var_dump($a, $b, $c, $arr);

$arr = ["one" => 1];
["one" => &$a, "three" => &$c] = $arr;
var_dump($arr);

function no_ref($a) { return $a; }
function &ref_return(&$a) { return $a; }
$x = [1, 2];
[&$v] = no_ref($x);
var_dump($v, $x);
$x = [1, 2];
[, &$v] = ref_return($x);
$v = 9;
var_dump($x);

$t = [0, 0];
$i = 0;
$src = [5, 6];
[&$t[$i++], &$t[$i++]] = $src;
$src[0] = 50;
var_dump($t, $i);
$u = [];
[&$u[]] = $src;
var_dump($u);

try {
    $s = "str";
    [&$z] = $s;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

class StorageNoRef implements ArrayAccess {
    private $s = [];
    function __construct(array $a) { $this->s = $a; }
    function offsetSet($k, $v): void { $this->s[$k] = $v; }
    function offsetGet($k): mixed { return $this->s[$k]; }
    function offsetExists($k): bool { return isset($this->s[$k]); }
    function offsetUnset($k): void { unset($this->s[$k]); }
}
class StorageRef implements ArrayAccess {
    private $s = [];
    function __construct(array $a) { $this->s = $a; }
    function offsetSet($k, $v): void { $this->s[$k] = $v; }
    function &offsetGet($k): mixed { return $this->s[$k]; }
    function offsetExists($k): bool { return isset($this->s[$k]); }
    function offsetUnset($k): void { unset($this->s[$k]); }
}
$o = new StorageNoRef([1, 2]);
[&$one, $two] = $o;
$one = 10;
var_dump($o);
$o = new StorageRef([1, 2]);
[&$one, $two] = $o;
$one = 10;
var_dump($o);
