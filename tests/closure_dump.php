<?php
// closures dump as the Closure objects php has: where they were written, what
// they capture and declare static, their bound object and parameters
class K { public $v = 1; function get() { return function ($a, &$b, ...$c) { return $this->v; }; } static function st() { return static fn(int $x = 5) => $x; } }
$y = 10; $z = [1];
$f = function ($p, $q = 2) use ($y, &$z) { static $s = 3; return $p; };
var_dump($f);
var_dump((new K)->get());
var_dump(K::st());
var_dump(fn() => 1);
var_dump(strlen(...));
var_dump((new K)->get(...));
var_dump(Closure::fromCallable('strtoupper'));
var_dump([function () {}]);
print_r($f); echo "\n";
var_dump(gettype($f), is_object($f), $f instanceof Closure, get_class($f));
var_export($f); echo "\n";
echo json_encode($f), "\n";
var_dump((array)$f);
class K2 { function __destruct() { echo "~K\n"; } function get() { return function () { return $this; }; } }
$c = (new K2)->get();
echo "made\n";
unset($c);
echo "unset\n";
var_dump(spl_object_id(new stdClass));
(new K2)->get();
echo "temp\n";
