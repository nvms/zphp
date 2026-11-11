<?php
// php's method lookup rules for calls: visibility of static calls, the
// calling class's own private method winning over a subclass's, instance
// methods called statically, and abstract methods
function attempt(callable $f) {
    try {
        $f();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

class Base {
    private static function hidden() { echo "Base::hidden\n"; }
    protected static function guarded() { echo "Base::guarded\n"; }
    private function own() { echo "Base::own\n"; }
    public function callOwn() { $this->own(); }
    public static function callHidden() { self::hidden(); Base::hidden(); }
    public function instance() { echo "Base::instance on ", get_class($this), "\n"; }
}
class Child extends Base {
    public function own() { echo "Child::own\n"; }
    public function viaParent() { Base::instance(); parent::guarded(); }
}
class Stranger {
    public function poke() { Base::instance(); }
}

Base::callHidden();
attempt(fn () => Base::hidden());
attempt(fn () => Base::guarded());
(new Child)->callOwn();
(new Child)->own();
(new Child)->viaParent();
attempt(fn () => (new Stranger)->poke());
attempt(fn () => Base::instance());

abstract class Shape {
    abstract public static function area();
    public static function describe() { return static::area(); }
}
class Square extends Shape {
    public static function area() { return 4; }
}
attempt(fn () => Shape::area());
echo Square::describe(), "\n";

interface Named {
    public static function name();
}
attempt(fn () => Named::name());

class Magic {
    private static function secret() { echo "secret\n"; }
    public static function __callStatic($name, $args) { echo "__callStatic($name)\n"; }
    public function __call($name, $args) { echo "__call($name)\n"; }
    public function inside() { Magic::missing(); }
}
Magic::secret();
Magic::missing();
(new Magic)->inside();
