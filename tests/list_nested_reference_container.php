<?php
// a nested list binding references fetches its container for writing: a
// missing or null element becomes the array the references go into
$arr = [1, 2];
list(, , list(&$var)) = $arr;
var_dump($arr);
$arr = [1, [5]];
list(, list(&$x)) = $arr;
$x = 9;
var_dump($arr);
$arr = [1, null];
[1 => [&$y]] = $arr;
var_dump($arr);
$f = [false];
[[&$d]] = $f;
var_dump($f);
$i = [5];
try { [[&$c]] = $i; } catch (Error $e) { echo $e->getMessage(), "\n"; }
$s = ['x' => 'str'];
try { ['x' => [&$b]] = $s; } catch (Error $e) { echo $e->getMessage(), "\n"; }

class StorageRef implements ArrayAccess {
    private $s = [];
    function __construct(array $a) { $this->s = $a; }
    function offsetSet($k, $v): void { $this->s[$k] = $v; }
    function &offsetGet($k): mixed { return $this->s[$k]; }
    function offsetExists($k): bool { return isset($this->s[$k]); }
    function offsetUnset($k): void { unset($this->s[$k]); }
}
$a = new StorageRef([1, 2]);
list(, , list(&$var)) = $a;
var_dump($a);
$a = new StorageRef([1, 2]);
list(, , list($var)) = $a;
var_dump($a);
