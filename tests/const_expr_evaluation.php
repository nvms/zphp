<?php
// constant expressions as php evaluates them: only an enum's properties may be
// read, nullsafe reads short-circuit, and a parameter default php can't fold
// (a property read, a dim fetch, a closure, a first-class callable) runs each
// time the argument is left out, in the function's class scope
namespace App;

enum Suit: string {
    case Hearts = 'H';
    case Spades = 'S';
}

class Plain {
    public $prop = 42;
}

class Box {
    const SIZES = ['small' => 1, 'large' => [3, 4]];
    const ZERO = 0;

    public function __construct(public $v = null) {}

    public function m($a = self::SIZES['large'][1], $b = Suit::Spades->value, $c = __CLASS__, $d = self::ZERO) {
        var_dump($a, $b, $c, $d);
    }

    public function closures($f = static function ($x) { return "closure $x"; }, $g = strrev(...), $h = self::helper(...)) {
        echo $f(1), "\n", $g('abc'), "\n", $h(), "\n";
    }

    public static function helper() {
        return __METHOD__;
    }
}

const NAME = Suit::Hearts->name;
const VALUE = Suit::Hearts?->value;
const MISSING = (null)?->value;
var_dump(NAME, VALUE, MISSING);

function name($s = Suit::Hearts->name, $t = new Box(Suit::Spades)) {
    var_dump($s, $t->v);
}
name();
name('given');

// each default an initializer computes stays alive while the next one runs
function several($a = new Box(v: [Suit::Hearts->name]), $b = [Suit::Spades->value], $c = new Box(v: 'c'), $d = Suit::Hearts?->name . '!') {
    var_dump($a, $b, $c, $d);
}
several();

function plain($p = (new Plain)->prop) {
    return $p;
}
for ($i = 0; $i < 2; $i++) {
    try {
        plain();
    } catch (\Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
var_dump(plain(7));

(new Box)->m();
(new Box)->closures();

// magic constants are case-insensitive
var_dump(__line__, __class__, basename(__file__), __namespace__);

function lines($a = __LINE__, $b = __function__) {
    var_dump($a, $b);
}
lines();

foreach (['name', 'plain', 'lines'] as $f) {
    echo new \ReflectionFunction(__NAMESPACE__ . '\\' . $f);
}
echo new \ReflectionMethod(Box::class, 'm');
echo new \ReflectionMethod(Box::class, 'closures');

$p = new \ReflectionParameter([Box::class, 'm'], 'd');
var_dump($p->isDefaultValueConstant(), $p->getDefaultValueConstantName());
$p = new \ReflectionParameter([Box::class, 'm'], 'a');
var_dump($p->isDefaultValueConstant());

#[\Attribute]
class Attr {
    public function __construct(public $v) {}
}

#[Attr(new Plain)]
#[Attr(Suit::Hearts->value)]
#[Attr(static function () { return 1; })]
function attributed() {}

foreach ((new \ReflectionFunction('App\attributed'))->getAttributes() as $attribute) {
    echo $attribute;
}
