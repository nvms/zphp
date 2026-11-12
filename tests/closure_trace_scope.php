<?php
// a closure's stack frame names its scope class, with -> when it has $this
class A {
    public $v = 1;
    function getClosure() { return function () { throw new Exception("in closure"); }; }
    static function getStatic() { return static function () { throw new Exception("in static"); }; }
}
$f = (new A)->getClosure();
try { $f(); } catch (Exception $e) { echo $e->getTraceAsString(), "\n"; }
$g = A::getStatic();
try { $g(); } catch (Exception $e) { echo $e->getTraceAsString(), "\n"; }
$h = function () { throw new Exception("plain"); };
try { $h(); } catch (Exception $e) { echo $e->getTraceAsString(), "\n"; }
$b = Closure::bind(function () { throw new Exception("bound"); }, new A, A::class);
try { $b(); } catch (Exception $e) { echo $e->getTraceAsString(), "\n"; }
try { array_map($f, [1]); } catch (Exception $e) { echo $e->getTraceAsString(), "\n"; }
