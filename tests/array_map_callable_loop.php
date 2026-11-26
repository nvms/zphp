<?php
// array_map() with a first-class callable or a partial application of
// literals runs as a loop in the calling frame (zend_compile_func_array_map):
// no array_map() frame in traces, the callback resolved per call
function frames(Throwable $e) {
    foreach ($e->getTrace() as $i => $f) {
        $name = str_starts_with($f['function'], '{closure') ? '{closure}' : $f['function'];
        echo "  #$i ", $name, " line ", $f['line'] ?? '-', "\n";
    }
}
function foo(string $v) { return $v . '!'; }
class K {
    static function s($v, $suffix = '?') { return $v . $suffix; }
    static function self_map($a) { return array_map(self::s(...), $a); }
    static function static_map($a) { return array_map(static::s(...), $a); }
}
class K2 extends K { static function s($v, $suffix = '#') { return "K2:" . $v . $suffix; } }
var_dump(array_map(foo(...), ['a' => 'x', 5 => 'y', 'z']));
var_dump(array_map(strtoupper(...), ['b' => 'q', 'r']));
var_dump(array_map(K::s(...), [1, 2]));
var_dump(array_map(K::s(?, '-'), [1, 2]));
var_dump(array_map(str_replace('a', 'b', ?), ['aa', 'ca']));
var_dump(array_map(foo(...), []));
var_dump(K2::self_map([1]), K2::static_map([1]));
$f = 'foo';
var_dump(array_map($f(...), [3]));
$c = 'K2';
var_dump(array_map($c::s(...), [3]));
try { array_map(foo(...), 'nope'); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { array_map(foo(...), null); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { array_map(foo(...), [[1]]); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { array_map(undefined_fn(...), [1]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
// a constant that isn't an array keeps the call: the callable is made first
try { array_map(Missing::m(...), "str"); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { array_map(Missing::m(...), 'a' . 'b'); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { array_map(Missing::m(...), -1); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $s = 'str'; array_map(Missing::m(...), $s); } catch (Error $e) { echo $e->getMessage(), "\n"; }
var_dump(array_map(undefined_fn(...), []));
function byref(&$x) { $x = 1; return $x; }
try { array_map(byref(...), [1]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
function thrower($v) { throw new Exception("t$v"); }
try { array_map(thrower(...), [7]); } catch (Exception $e) { echo $e->getMessage(), "\n"; frames($e); }
try { array_map(fn($v) => thrower($v), [8]); } catch (Exception $e) { echo $e->getMessage(), "\n"; frames($e); }
try { array_map(K::s(...), [1], [2]); array_map(thrower(?), [9]); } catch (Exception $e) { echo $e->getMessage(), "\n"; frames($e); }
foreach ([1, 2] as $n) {
    try { var_dump(array_map(thrower(...), [$n])); } catch (Exception $e) { echo "caught ", $e->getMessage(), "\n"; }
}
echo implode(',', array_map(foo(...), ['a', 'b'])), "\n";
var_dump(array_map(foo(...), array_map(strrev(...), ['ab', 'cd'])));
var_dump(\array_map(foo(...), ['q']));
$x = 'shared';
$withref = ['k' => &$x, 'v'];
var_dump(array_map(strtoupper(...), $withref));
var_dump(array_map(foo(...), ['0' => 'a', '1x' => 'b', -5 => 'c']));
$r = array_map(intval(...), ['1', '2']);
$r[] = 3;
var_dump($r);
echo count(array_map(fn($x) => $x * 2, [1, 2])), "\n";
var_dump(array_map(foo(...), [1, 2], [3]));
function g() { return array_map(foo(...), ['in']); }
var_dump(g());
$gen = (function () { yield array_map(foo(...), ['y']); })();
var_dump($gen->current());
class D { function __destruct() { echo "destruct\n"; } }
function keep($o) { return 1; }
array_map(keep(...), [new D]);
echo "after\n";
