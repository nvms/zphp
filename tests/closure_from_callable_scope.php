<?php
class Foo {
    protected static function ps($p) { return $p; }
    private function pv($p) { return $p; }
    function closePriv() { return Closure::fromCallable([$this, 'pv']); }
}
class SubFoo extends Foo {
    function closePS() { return Closure::fromCallable([__CLASS__, 'ps']); }
    function closePS2() { return Closure::fromCallable(['Foo', 'ps']); }
    function closePS3() { return Closure::fromCallable([$this, 'ps']); }
}
$s = new SubFoo;
echo $s->closePS3()("a"), "\n";
echo $s->closePS2()("b"), "\n";
echo $s->closePS()("c"), "\n";
echo $s->closePriv()("d"), "\n";
class A { function method() {} }
try { Closure::fromCallable(["A", "method"]); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { Closure::fromCallable("nope"); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { Closure::fromCallable([new A, "nope"]); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
try { Closure::fromCallable(42); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
class M { function __call($n, $a) { return "call $n"; } static function __callStatic($n, $a) { return "static $n"; } }
$f = Closure::fromCallable([new M, "x"]); echo $f(), "\n";
$f = Closure::fromCallable("M::y"); echo $f(), "\n";
class P { function __invoke($a) { return "inv $a"; } }
$f = Closure::fromCallable(new P); echo $f(1), "\n";
function g() { return Closure::fromCallable([new Foo, "pv"]); }
try { g(); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
echo (new SubFoo)->closePriv()("e"), "\n";
