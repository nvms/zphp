<?php
// reading a variable that was never assigned (or was unset) warns and reads
// null; isset, ??, ??=, empty(), a by-reference argument, and every write
// stay quiet, and $this outside an object is an Error
echo $a;
var_dump($b ?? 'd', isset($c), empty($d));
function f() { return $x; }
var_dump(f());
function g() { $y = null; return $y; }
var_dump(g());
preg_match('/a/', 'a', $m); var_dump($m);
$arr[] = 1; var_dump($arr);
$s .= 'x'; var_dump($s);
$i++; var_dump($i);
unset($arr); var_dump($arr ?? 'gone'); echo $arr;
function h() { static $n; return $n; } var_dump(h());
foreach ([1] as $v) {} var_dump($v);
list($p, $q) = [1]; var_dump($q);
$fn = function () use ($undef_capture) { return $undef_capture; }; var_dump($fn());
class C { static function s() { return isset($this); } } var_dump(C::s());
function t2() { return $this; }
try { t2(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
$r = &$undefRef; var_dump($undefRef);
function byRef(&$x) { } byRef($newVar); var_dump($newVar);
var_dump(compact('nothere', 'r'));
$nullVar = null; var_dump(compact('nullVar'), get_defined_vars()['nullVar'] ?? 'missing');
$fromParent = 'p';
var_dump($setInInclude);
function gen() { yield $y ?? 'gy'; $z = 1; yield $z; }
foreach (gen() as $v) var_dump($v);
function useGlobal() { global $g; var_dump($g); $g = 2; }
useGlobal(); var_dump($g);
function st() { static $s; $s++; return $s; } var_dump(st(), st());
$arr = []; $arr['k'] ??= 'def'; var_dump($arr);
$q ??= 'q'; var_dump($q);
[$l1, [$l2]] = [1, [2]]; var_dump($l1 + $l2);
foreach ([1, 2] as $k => $v2) {} var_dump($k);
try { throw new Exception('e'); } catch (Exception $ex) {} var_dump($ex instanceof Exception);
$fn = fn() => $outer ?? 'arrow-null'; var_dump($fn());
$closure = function () use (&$byRefCap) { $byRefCap = 5; }; $closure(); var_dump($byRefCap);
unset($q); var_dump(isset($q));
echo "$undefinedInString\n";
