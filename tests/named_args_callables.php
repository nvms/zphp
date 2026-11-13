<?php
class T { function m($a = 'a', $b = 'b') { echo "a=$a b=$b\n"; } static function s($a = 'a', $b = 'b') { echo "s a=$a b=$b\n"; }
  function __call($n, $args) { var_dump($n, $args); } static function __callStatic($n, $args) { var_dump($n, $args); } }
$o = new T;
[$o, 'm'](...['b' => 2]);
[$o, 'm'](b: 3);
'T::s'(b: 4);
['T', 's'](...['b' => 5]);
$f = $o->m(...); $f(b: 6);
$f = T::s(...); $f(b: 7);
$o->zz(1, b: 8);
T::yy(1, b: 9);
$f = $o->ww(...); $f(1, b: 10);
$c = function ($a = 'a', $b = 'b') { echo "c a=$a b=$b\n"; };
$c(...['b' => 11]);
$c->__invoke(b: 12);
call_user_func([$o, 'm'], b: 13);
call_user_func_array([$o, 'm'], ['b' => 14]);
call_user_func_array('T::s', ['b' => 15]);
call_user_func_array([$o, 'qq'], [1, 'b' => 16]);
try { call_user_func_array([$o, 'm'], ['c' => 1]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { call_user_func_array([$o, 'm'], ['a' => 1, 2]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $o->m(1, a: 2); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $o->m(c: 2); } catch (Error $e) { echo $e->getMessage(), "\n"; }
function v($a, ...$rest) { var_dump($a, $rest); }
call_user_func('v', 1, x: 2);
call_user_func_array('v', [1, 2, 'y' => 3]);
$fv = v(...);
$fv(1, z: 4);
function needs($a, $b) { echo "$a $b\n"; }
try { needs(b: 1); } catch (ArgumentCountError $e) { echo $e->getMessage(), "\n"; }
try { call_user_func('needs', b: 1); } catch (ArgumentCountError $e) { echo $e->getMessage(), "\n"; }
function byref(&$r) { $r++; }
call_user_func('byref', r: 1);
call_user_func_array('str_replace', ['a', 'b', 'c', 'count' => 0]);
class Inv { function __invoke($a = 1, $b = 2) { echo "inv $a $b\n"; } }
$inv = new Inv;
$inv(b: 5);
call_user_func($inv, b: 6);
$cl = function ($a = 'a', $b = 'b') { echo "cl $a $b\n"; };
$cl->call(new stdClass, b: 7);
$rf = new ReflectionFunction('needs');
$rf->invoke(b: 8, a: 9);
$rm = new ReflectionMethod('T', 'm');
$rm->invoke($o, b: 10);
class Dyn { function __call($m, $args) { $this->{'_' . $m}(...$args); } private function _go($a = 'a', $b = 'b') { echo "go $a $b\n"; } }
(new Dyn)->go(b: 11);
