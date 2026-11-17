<?php
// a static call through a class in a variable or an object follows the same
// rules as one naming the class: visibility, __callStatic, and instance
// methods only on a fitting $this

class Foo {
    private function a() { var_dump(1); }
    public function b() { var_dump(isset($this) ? get_class($this) : 'no this'); }
    protected function c() { var_dump(3); }
    public static function s() { var_dump(static::class); }
    public static function __callStatic($name, $args) { var_dump('__callStatic::' . $name); }
    public function __call($name, $args) { var_dump('__call::' . $name); }

    public function inside(object $o, string $c) {
        foreach ([fn () => $c::a(), fn () => $o::c(), fn () => $c::b(), fn () => $o::b()] as $call) {
            try {
                $call();
            } catch (Error $e) {
                echo $e->getMessage(), "\n";
            }
        }
    }
}

class Bar extends Foo {
    public function viaChild(string $c) {
        foreach ([fn () => $c::a(), fn () => $c::c(), fn () => $c::b()] as $call) {
            try {
                $call();
            } catch (Error $e) {
                echo $e->getMessage(), "\n";
            }
        }
    }
}

class Plain {
    public function m() { echo "m\n"; }
}

$x = new Foo;
$c = 'Foo';
foreach ([fn () => $c::a(), fn () => $x::a(), fn () => $c::c(), fn () => $x::c(), fn () => $c::b(), fn () => $x::b(), fn () => $c::s(), fn () => $x::s(), fn () => $c::missing()] as $call) {
    try {
        $call();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$x->inside(new Bar, 'Foo');
(new Bar)->viaChild('Foo');

$p = 'Plain';
foreach (['m', 'nope'] as $m) {
    try {
        $p::$m();
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
try {
    $p::m();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    $p::nope();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$b = 'bar';
$b::s();
