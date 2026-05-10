<?php
trait Greeter {
    public function hello(): string {
        return "hello, " . $this->name();
    }
    abstract public function name(): string;
}
class Alice {
    use Greeter;
    public function name(): string { return "alice"; }
}
echo (new Alice)->hello(), "\n";

trait Counter {
    private int $count = 0;
    public function inc(): int { return ++$this->count; }
    public function val(): int { return $this->count; }
}
class C { use Counter; }
$c = new C;
echo $c->inc(), " ", $c->inc(), " ", $c->val(), "\n";

// trait static-var isolation per using class (architectural - shared in zphp)

// trait conflict resolution insteadof + `as` aliasing (architectural - aliasing not wired)
trait A { public function go(): string { return "A"; } }
trait B { public function go2(): string { return "B"; } }
class AB { use A, B; }
$ab = new AB;
echo $ab->go(), " ", $ab->go2(), "\n";

// trait constants (PHP 8.2+)
trait Constants {
    public const VERSION = "1.0";
    public const MAX = 100;
}
class CC { use Constants; }
echo CC::VERSION, " ", CC::MAX, "\n";

// trait inheritance via use chain
trait Base {
    public function ping(): string { return "base"; }
}
trait Mid {
    use Base;
    public function mid(): string { return "mid"; }
}
class Foo { use Mid; }
$f = new Foo;
echo $f->ping(), " ", $f->mid(), "\n";

// multiple use chained
trait T1 { public function t1(): string { return "t1"; } }
trait T2 { use T1; public function t2(): string { return "t2"; } }
trait T3 { use T2; public function t3(): string { return "t3"; } }
class Multi { use T3; }
$m = new Multi;
echo $m->t1(), " ", $m->t2(), " ", $m->t3(), "\n";

// multiple traits
trait Sayable { public function say(): string { return "saying"; } }
trait Doable { public function do_(): string { return "doing"; } }
class Both {
    use Sayable, Doable;
}
$b = new Both;
echo $b->say(), " ", $b->do_(), "\n";

// trait abstract method enforcement
trait NeedsName {
    abstract public function name(): string;
    public function greet(): string { return "Hi, " . $this->name(); }
}
class WithName {
    use NeedsName;
    public function name(): string { return "Bob"; }
}
echo (new WithName)->greet(), "\n";

// trait property defaults
trait Defaults {
    public string $color = "red";
    public int $size = 10;
}
class D { use Defaults; }
$d = new D;
echo $d->color, " ", $d->size, "\n";
$d->color = "blue";
echo $d->color, "\n";

// trait with self vs static
trait Identifiable {
    public static function whoAmI(): string {
        return "trait-said:" . static::class;
    }
}
class Cat { use Identifiable; }
class Dog { use Identifiable; }
echo Cat::whoAmI(), " ", Dog::whoAmI(), "\n";

// trait method aliasing via `as` (architectural - not wired yet)
// trait conflict detection via eval (architectural - eval not implemented)

// trait constant inheritance
trait HasC {
    public const NAME = "trait-name";
}
class WithC {
    use HasC;
}
echo WithC::NAME, "\n";

// trait method same as class - class wins
trait TraitMethod {
    public function go(): string { return "trait"; }
}
class ClassWins {
    use TraitMethod;
    public function go(): string { return "class"; }
}
echo (new ClassWins)->go(), "\n";

// method override in subclass beats trait
class GrandFoo {
    use TraitMethod;
}
class GrandBar extends GrandFoo {
    public function go(): string { return "sub"; }
}
echo (new GrandBar)->go(), "\n";

// trait via instanceof
trait Marker {}
class Mk { use Marker; }
$mk = new Mk;
var_dump(method_exists($mk, "say"));
echo class_uses(Mk::class) ? "uses-array" : "no", "\n";
print_r(class_uses(Mk::class));
