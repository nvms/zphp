<?php
// a closure of a method __call or __callStatic answers reflects the trampoline: a
// first-class callable takes mixed ...$arguments, Closure::fromCallable nothing
class Test {
    public function __call($name, $args) { var_dump($name, $args); }
    public static function __callStatic($name, $args) { var_dump($name, $args); }
}
$t = new Test;
foreach ([Test::fail(...), $t->other(...), Closure::fromCallable([$t, 'x']), Closure::fromCallable('Test::y')] as $c) {
    $r = new ReflectionFunction($c);
    var_dump($r->getName(), $r->getNumberOfParameters(), $r->getNumberOfRequiredParameters(), $r->isVariadic());
    $p = $r->getParameters();
    var_dump(count($p));
    if ($p) {
        var_dump($p[0]->getName(), $p[0]->isVariadic(), $p[0]->getPosition(), $p[0]->isOptional(), (string) $p[0]->getType(), $p[0]->allowsNull(), $p[0]->hasType());
        echo $p[0], "\n";
    }
    echo $r;
    var_dump($r->hasReturnType(), $r->isUserDefined(), $r->isInternal());
}
$m = new ReflectionMethod(Test::fail(...), '__invoke');
var_dump($m->getNumberOfParameters());
$c = Test::fail(...);
$d = clone $c;
var_dump((new ReflectionFunction($d))->getNumberOfParameters());
$t->named(...)(1, a: 2);
