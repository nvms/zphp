<?php
// ReflectionProperty::getModifiers() includes IS_VIRTUAL for a hooked
// property without a backing value; array_multisort's and extract's
// by-reference parameters accept values; a closure made from a callable is a
// closure to ReflectionFunction

class C {
    public $plain;
    public $backed { set { $this->backed = strtoupper($value); } }
    public $virtual { get { return 42; } }
    public static $static;
}
foreach (['plain', 'backed', 'virtual', 'static'] as $name) {
    $p = new ReflectionProperty('C', $name);
    echo $name, ": ", $p->getModifiers(), " ", var_export($p->isVirtual(), true), "\n";
    echo "  ", implode(' ', Reflection::getModifierNames($p->getModifiers())), "\n";
}

foreach (['array_multisort', 'extract', 'sort', 'preg_match'] as $fn) {
    foreach ((new ReflectionFunction($fn))->getParameters() as $param) {
        if ($param->isPassedByReference()) {
            echo $fn, " $", $param->getName(), ": ", var_export($param->canBePassedByValue(), true), "\n";
        }
    }
}
function user(&$a, $b) {}
foreach ((new ReflectionFunction('user'))->getParameters() as $param) {
    echo "user $", $param->getName(), ": ", var_export($param->canBePassedByValue(), true), "\n";
}

class M {
    public function method() {}
}
$closure = (new ReflectionMethod(new M, 'method'))->getClosure(new M);
$r = new ReflectionFunction($closure);
var_dump($r->isClosure());
var_dump((new ReflectionFunction(strlen(...)))->isClosure());
var_dump((new ReflectionFunction(Closure::fromCallable('strlen')))->isClosure());
var_dump((new ReflectionFunction(fn() => 1))->isClosure());
var_dump((new ReflectionFunction('strlen'))->isClosure());
var_dump((new ReflectionFunction(strlen(...)))->isAnonymous());
var_dump((new ReflectionFunction(fn() => 1))->isAnonymous());
