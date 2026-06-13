<?php
// covers: PHP early-binds (relocates before main execution) top-level class and
// interface declarations that are self-sufficient at their declaration point -
// no parent or a parent already bound, no interfaces, no traits, not an enum.
// such a class is usable before its textual declaration. declarations that are
// NOT self-sufficient (implements, traits, forward parent, conditional) bind at
// runtime and are NOT visible before their declaration, matching PHP exactly

// simple class with no dependencies
$o = new Simple();
echo $o->greet(), "\n";
class Simple {
    public function greet() { return 'simple'; }
}

// parent declared earlier in source order: both early-bound
$b = new Child();
echo $b->who(), "\n";
class Parent1 { public function who() { return 'parent'; } }
class Child extends Parent1 { public function who() { return 'child'; } }

// three-level chain, used before, declared in dependency order
$c = new Leaf();
echo $c->v, "\n";
class Root { public $v = 'root'; }
class Mid extends Root {}
class Leaf extends Mid { public $v = 'leaf'; }

// literal property/static/const defaults are order-independent and hoist-safe
$d = new WithDefaults();
echo $d->n, ' ', $d->arr[1], ' ', WithDefaults::TAG, ' ', WithDefaults::$count, "\n";
class WithDefaults {
    public int $n = 42;
    public array $arr = [10, 20, 30];
    public static int $count = 7;
    const TAG = 'tag';
}

// self::CONST default resolves against the class itself (registered before its
// own defaults run), regardless of declaration position
$e = new SelfRef();
echo $e->p, "\n";
class SelfRef {
    const A = 99;
    public $p = self::A;
}

// interface usable before its declaration; its constant resolves
echo Contract::VERSION, "\n";
interface Contract { const VERSION = 3; }

// class constant read before the class is declared
var_dump(Config::MAX);
class Config { const MAX = 100; }

// a class that implements an interface is NOT early-bound: not visible before
// its declaration even though the interface precedes it
var_dump(class_exists('Implementer', false));
interface Marker {}
class Implementer implements Marker {}
var_dump(class_exists('Implementer', false));

// a class using a trait is NOT early-bound
var_dump(class_exists('TraitUser', false));
trait Behavior { public function act() { return 'act'; } }
class TraitUser { use Behavior; }
var_dump(class_exists('TraitUser', false));

// a conditionally-declared class binds at runtime, not before
var_dump(class_exists('Conditional', false));
if (true) {
    class Conditional {}
}
var_dump(class_exists('Conditional', false));

// a class whose property default references an external constant is NOT
// relocated ahead of that constant - it binds at its declaration site, so the
// default still evaluates correctly (PHP evaluates property defaults lazily)
const EXTERNAL = 'ext';
class UsesExternal {
    public string $mode = EXTERNAL;
}
echo (new UsesExternal())->mode, "\n";
