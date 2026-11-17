<?php
// methods php declares on ReflectionFunctionAbstract and ReflectionType
// report the parent as their declaring class and still read the object the
// way its own class does

$m = new ReflectionMethod('ReflectionMethod', 'getName');
var_dump($m->class, $m->getDeclaringClass()->name);
$m = new ReflectionMethod('ReflectionNamedType', 'allowsNull');
var_dump($m->class);
var_dump((new ReflectionMethod('ReflectionNamedType', 'getName'))->class);

function f(?int $x): string { return ''; }
$r = new ReflectionFunction('f');
var_dump($r->getName(), $r->isClosure(), (string) $r->getReturnType());
var_dump($r->getParameters()[0]->getType()->allowsNull(), (string) $r->getParameters()[0]->getType());
var_dump($r->hasTentativeReturnType(), $r->getTentativeReturnType());

class A { function m(int|string $a) {} }
$rm = new ReflectionMethod('A', 'm');
var_dump($rm->getName(), $rm->isClosure(), $rm->getClosureThis(), $rm->getClosureUsedVariables());
var_dump((string) $rm->getParameters()[0]->getType(), $rm->getParameters()[0]->getType()->allowsNull());

foreach (['ReflectionMethod', 'ReflectionFunction', 'ReflectionNamedType', 'ReflectionUnionType'] as $c) {
    $names = [];
    foreach ((new ReflectionClass($c))->getMethods() as $method) $names[] = $method->class . '::' . $method->name;
    echo implode(",", $names), "\n";
}
echo new ReflectionMethod('ReflectionFunctionAbstract', 'getName');

try {
    $rm->getName(1);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

// a reflector's declared name and class can't be written
#[AllowDynamicProperties]
class MethodEx extends ReflectionMethod {
    public $foo = "xyz";
}
$x = new MethodEx('A', 'm');
foreach (['class', 'name'] as $prop) {
    try {
        $x->$prop = 'other';
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
}
$x->foo = 'bar';
$x->bar = 'baz';
var_dump($x->class, $x->name, $x->foo, $x->bar);
try {
    $rc = new ReflectionClass('A');
    $rc->name = 'B';
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
