<?php
// internal functions
$r = str_replace(?, ?, 'hello world');
var_dump($r('o', '0'));
echo new ReflectionFunction($r);
$p = str_pad(?, 10, ...);
var_dump($p('x'), $p('x', '-'), $p('x', '-', STR_PAD_LEFT));
echo new ReflectionFunction($p);
$m = array_map(strtoupper(...), ?);
var_dump($m(['a', 'b']));
$in = in_array(?, [1, 2, 3], true);
var_dump($in(2), $in('2'));
// by reference
function inc(&$x, $by = 1) { $x += $by; }
$v = 1;
$i = inc($v, ?);
$i(5);
var_dump($v);
$j = inc(?, 10);
$w = 3;
$j($w);
var_dump($w);
$s = sort(?);
$arr = [3, 1, 2];
$s($arr);
var_dump($arr);
// method on object and static
class A {
    private $n = 'A';
    public function hi($greet, $name = 'world') { return "$greet $name from {$this->n}"; }
    public static function make(...$xs) { return static::class . ':' . implode(',', $xs); }
    private function secret($x) { return "secret $x"; }
    public function getSecret() { return $this->secret(?); }
}
class B extends A {}
$a = new A;
$h = $a->hi('hey', ?);
var_dump($h('you'));
$h2 = $a->hi(?);
var_dump($h2('yo'));
$mk = B::make(1, ?, ...);
var_dump($mk(2, 3, 4));
var_dump($a->getSecret()('x'));
// nested
$add = fn($a, $b, $c) => $a + $b + $c;
$add1 = $add(1, ?, ?);
$add12 = $add1(2, ?);
var_dump($add12(3));
var_dump($add12);
// named
function n($a, $b = 2, $c = 3, ...$rest) { return func_get_args(); }
$f = n(c: ?, a: 1);
var_dump($f(30));
$g = n(1, ?, c: ?);
echo new ReflectionFunction($g);
var_dump($g(20, 30));
try { n(1, x: ?); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
try { strlen(x: ?); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
try { strlen(?, ?); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
try { undefined_fn(?); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
try { $a->nope(?); } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
// __invoke object
class Inv { function __invoke($x, $y) { return $x * $y; } }
$iv = (new Inv)(?, 3);
var_dump($iv(4));
var_dump($iv);
// typed and coercion
function typed(int $a, string ...$s): string { return $a . implode('', $s); }
$t = typed('5', ...);
var_dump($t('a', 'b'));
try { typed('x', ?); } catch (TypeError $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
echo new ReflectionFunction($t);
// stack trace
function thrower($a, $b) { throw new Exception('boom'); }
try { thrower(1, ?)(2); } catch (Exception $e) { echo $e->getTraceAsString(), "\n"; }
// serialization and clone
try { serialize(strlen(?)); } catch (Exception $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
$cl = clone $h;
var_dump($cl('z'));
var_dump((new ReflectionFunction($h))->getClosureThis() === $a);
var_dump((new ReflectionFunction($h))->getClosureScopeClass()->name);
var_dump((new ReflectionFunction($h))->getName());
var_dump((new ReflectionFunction($h))->isStatic(), (new ReflectionFunction(strlen(?)))->isStatic());
