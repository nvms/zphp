<?php
// closures and arrow functions may return by reference
$counter = function &() { static $n = 0; return $n; };
$n = &$counter();
$n += 5;
echo $counter(), "\n";
$first = fn&(array &$list) => $list[0];
$items = [1, 2];
$slot = &$first($items);
$slot = 'changed';
var_dump($items);
$static = static function &() { static $v = 'a'; return $v; };
$v = &$static();
$v = 'b';
echo $static(), "\n";
function &plain() { static $p; return $p; }
class Holder { public $p; public function &get() { return $this->p; } public function copy() { return $this->p; } }
foreach ([new ReflectionFunction($counter), new ReflectionFunction($first), new ReflectionFunction(fn() => 1), new ReflectionFunction('plain'), new ReflectionFunction('strlen'), new ReflectionMethod('Holder', 'get'), new ReflectionMethod('Holder', 'copy')] as $r) {
    var_dump($r->returnsReference());
}
