<?php
// a plain function has no class scope, even when a method the engine runs
// (__get, __set, __call) calls it

function setProp($obj) { $obj->prop = 42; }
function getProp($obj) { var_dump($obj->prop); }
function calledClass() { try { var_dump(get_called_class()); } catch (Error $e) { echo $e->getMessage(), "\n"; } }

class Test {
    private $prop;
    public function __get($k) { calledClass(); getProp($this); }
    public function __set($k, $v) { calledClass(); setProp($this); }
    public function __call($name, $args) { calledClass(); setProp($this); }
    public static function __callStatic($name, $args) { calledClass(); }
    public function plain() { calledClass(); }
}

$test = new Test;
try { $test->prop = "bar"; } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { var_dump($test->prop); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { $test->missing(); } catch (Error $e) { echo $e->getMessage(), "\n"; }
Test::missingStatic();
$test->plain();

class Scoped {
    private $secret = 'secret';
    public function closure() {
        return function () { return $this->secret . ' ' . static::class; };
    }
    public function arrow() {
        $f = fn() => static::class;
        return $f();
    }
}
class ScopedChild extends Scoped {}
var_dump((new ScopedChild)->closure()());
var_dump((new ScopedChild)->arrow());
