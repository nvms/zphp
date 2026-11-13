<?php
class A { private $p = 1; function m($x) { return $x * 2; } static function s() { return static::class; } }
class B extends A {}
$f = strlen(...);
$g = clone $f;
var_dump($g("abc"), $f == $g);
var_dump((array)$f, get_object_vars($f));
$m = (new A)->m(...);
$c = clone $m;
var_dump($c(4));
var_dump(serialize([1]) && true);
try { serialize($f); } catch (Exception $e) { echo $e->getMessage(), "\n"; }
var_dump(json_encode($f));
var_export($f); echo "\n";
print_r($m); echo "\n";
$s = B::s(...);
var_dump($s(), (clone $s)());
foreach ($f as $k => $v) echo "$k\n";
var_dump(isset($f->x));
try { $f->x = 1; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { var_dump($f->x); } catch (Error $e) { echo $e->getMessage(), "\n"; }
class Holder { public $f; function m() {} function __destruct() { echo "destroyed\n"; } }
$h = new Holder;
$h->f = $h->m(...);
unset($h);
var_dump(gc_collect_cycles());
$h = new Holder;
$h->f = Closure::fromCallable([$h, "m"]);
$h->f = null;
unset($h);
echo "end\n";
