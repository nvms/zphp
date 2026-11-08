<?php
// attribute arguments are evaluated in the scope of the class reflection
// reads them from: a trait method's in the class using it, a closure's in
// the class it is bound to; attributes before a group apply to every member
#[Attribute(Attribute::TARGET_ALL | Attribute::IS_REPEATABLE)]
class A { function __construct(public $v = null, public $w = null) {} }

trait T {
    #[A(self::class, self::FOO)]
    public function m(#[A(self::class)] $p) {}
}
class UsesT { use T; private const FOO = 'uses'; }
class Other { private const FOO = 'other'; }
class Home {
    private const FOO = 'home';
    #[A(1)] public const X = 1, Y = 2;
    #[A(2)] public $a, $b;
    static function make() { return #[A(self::class, self::FOO)] function (#[A(self::FOO)] $p) {}; }
}
function args(ReflectionAttribute $a) { try { return $a->getArguments(); } catch (Error $e) { return $e->getMessage(); } }

$m = new ReflectionMethod('UsesT', 'm');
var_dump(args($m->getAttributes()[0]));
var_dump(args($m->getParameters()[0]->getAttributes()[0]));
var_dump(args((new ReflectionMethod('T', 'm'))->getAttributes()[0]));

foreach (['X', 'Y'] as $c) var_dump(args((new ReflectionClassConstant('Home', $c))->getAttributes()[0]));
foreach (['a', 'b'] as $p) var_dump(args((new ReflectionProperty('Home', $p))->getAttributes()[0]));

$f = new ReflectionFunction(Home::make());
var_dump(args($f->getAttributes()[0]), args($f->getParameters()[0]->getAttributes()[0]));
$bound = new ReflectionFunction(Home::make()->bindTo(null, Other::class));
var_dump(args($bound->getAttributes()[0]), args($bound->getParameters()[0]->getAttributes()[0]));

function plain(#[A(PHP_INT_SIZE)] $x, #[SensitiveParameter] $secret) {}
foreach ((new ReflectionFunction('plain'))->getParameters() as $p) {
    foreach ($p->getAttributes() as $a) var_dump($a->getName(), args($a));
}
