<?php
// regression: an instance-property default that references a class constant
// (`self::CONST`, `OtherClass::CONST`, or a compound expression of them)
// resolved to null. property defaults were evaluated in a prelude that runs
// before the class is registered, so `self::` saw nothing. they are now
// installed after class_decl via set_prop_default.

class C {
    const A = 100;
    const B = 5;
    public int $bare = self::A;
    public int $compound = self::A | self::B;
    public int $arith = self::A + self::B;
    public string $cls = self::class;
}
$c = new C;
var_dump($c->bare, $c->compound, $c->arith, $c->cls);

// the canonical Symfony JsonResponse pattern
class JsonResponse {
    public const DEFAULT_ENCODING_OPTIONS = 15;
    protected int $encodingOptions = self::DEFAULT_ENCODING_OPTIONS;
    public function opts(): int { return $this->encodingOptions; }
}
echo (new JsonResponse)->opts(), "\n"; // 15

// inherited property default referencing the parent's constant
class Base {
    const LIMIT = 50;
    public int $max = self::LIMIT;
}
class Child extends Base {
    public int $min = 0;
}
$ch = new Child;
echo $ch->max, " ", $ch->min, "\n"; // 50 0

// default referencing another class's constant
class Settings { const VERSION = 7; }
class App {
    public int $v = Settings::VERSION + 1;
    public string $name = Settings::VERSION . '-app';
}
$a = new App;
echo $a->v, " ", $a->name, "\n"; // 8 7-app

// array property default with constant elements
class Permissions {
    const READ = 1;
    const WRITE = 2;
    public array $all = [self::READ, self::WRITE, self::READ | self::WRITE];
}
print_r((new Permissions)->all); // [1, 2, 3]

// enum case as a property default
enum Suit { case Hearts; case Spades; }
class Card {
    public Suit $suit = Suit::Hearts;
}
echo (new Card)->suit->name, "\n"; // Hearts

// each instance gets an independent copy of an array default
class Bag { public array $items = []; }
$b1 = new Bag; $b1->items[] = 'x';
$b2 = new Bag;
echo count($b1->items), " ", count($b2->items), "\n"; // 1 0

// a property default that is a plain literal still works
class Plain {
    public int $n = 42;
    public string $s = 'hello';
    public bool $flag = true;
}
$p = new Plain;
var_dump($p->n, $p->s, $p->flag);
