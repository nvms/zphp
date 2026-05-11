<?php
class Base {
    public static function create(): static { return new static; }
    public static function name(): string { return static::class; }
    public static function selfName(): string { return self::class; }
    public function whoami(): string { return static::class; }
    public function selfWho(): string { return self::class; }
}
class Child extends Base {}
class Grandchild extends Child {}

echo Base::name(), " ", Child::name(), " ", Grandchild::name(), "\n";
echo Base::selfName(), " ", Child::selfName(), " ", Grandchild::selfName(), "\n";

$b = Base::create();
$c = Child::create();
$g = Grandchild::create();
echo get_class($b), " ", get_class($c), " ", get_class($g), "\n";
echo $b->whoami(), " ", $c->whoami(), " ", $g->whoami(), "\n";
echo $b->selfWho(), " ", $c->selfWho(), " ", $g->selfWho(), "\n";

class A {
    public function dispatch(): string { return static::handle(); }
    public static function handle(): string { return "A::handle"; }
}
class B extends A {
    public static function handle(): string { return "B::handle"; }
}
class C2 extends B {
    public static function handle(): string { return "C2::handle"; }
}

echo (new A)->dispatch(), "\n";
echo (new B)->dispatch(), "\n";
echo (new C2)->dispatch(), "\n";

class Counter {
    protected static int $count = 0;
    public static function increment(): int { return ++static::$count; }
    public static function get(): int { return static::$count; }
}
class SubCounter extends Counter {
    protected static int $count = 100;
}

echo Counter::increment(), " ", Counter::increment(), "\n";
echo SubCounter::increment(), " ", SubCounter::increment(), "\n";
echo Counter::get(), " ", SubCounter::get(), "\n";

class P {
    public static function go(): string { return "parent"; }
}
class S extends P {
    public static function go(): string { return parent::go() . "-sub"; }
}
echo S::go(), "\n";

class Factory {
    public static function build(): static { return new static; }
}
class Widget extends Factory { public string $type = "widget"; }
class Button extends Widget { public string $type = "button"; }
echo Widget::build()->type, " ", Button::build()->type, "\n";
echo get_class(Widget::build()), " ", get_class(Button::build()), "\n";

class Caller {
    public static function direct(): string { return get_called_class(); }
    public static function chain(): string { return static::direct(); }
}
class Called extends Caller {}
echo Caller::direct(), " ", Called::direct(), "\n";
echo Caller::chain(), " ", Called::chain(), "\n";

class Chain {
    public function self(): static { return $this; }
    public function get(): string { return static::class; }
}
class Link extends Chain {}
echo (new Link)->self()->self()->get(), "\n";

class Fluent {
    public function with(string $key): static { return clone $this; }
}
class FluentChild extends Fluent {}
echo get_class((new FluentChild)->with("x")), "\n";

class Fwd {
    public static function forward(): string { return forward_static_call([static::class, "go"]); }
    public static function go(): string { return "Fwd::go"; }
}
class FwdChild extends Fwd {
    public static function go(): string { return "FwdChild::go"; }
}
echo Fwd::forward(), "\n";
echo FwdChild::forward(), "\n";
