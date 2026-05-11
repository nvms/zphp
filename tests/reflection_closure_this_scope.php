<?php
class Box {
    private int $val = 42;
    public function getReader(): Closure { return fn() => $this->val; }
}

$b = new Box;
$reader = $b->getReader();
echo $reader(), "\n";

$reader_other = $reader->bindTo(new Box, Box::class);
echo $reader_other(), "\n";

$cl_bound = (function() { return $this->val; })->bindTo($b, Box::class);
$rf = new ReflectionFunction($cl_bound);
echo $rf->getClosureThis() === $b ? "y" : "n", "\n";
echo $rf->getClosureScopeClass()->getName(), "\n";

$cl_unbound = function() {};
$rf = new ReflectionFunction($cl_unbound);
echo $rf->getClosureThis() === null ? "y" : "n", "\n";

$cl = function() {};
$rf = new ReflectionFunction($cl);
echo $rf->isClosure() ? "y" : "n", "\n";

echo Closure::class, "\n";

function takeCallable(callable $c): mixed { return $c(); }
echo takeCallable(function() { return "ok"; }), "\n";
echo takeCallable(fn() => "arrow"), "\n";

class WithMagic { public function __invoke(): string { return "invoked"; } }
echo takeCallable(new WithMagic), "\n";

$rf2 = new ReflectionFunction(fn($a, $b = 10, ...$rest) => $a + $b);
echo $rf2->getNumberOfParameters(), "\n";
echo $rf2->getNumberOfRequiredParameters(), "\n";
foreach ($rf2->getParameters() as $p) {
    echo $p->getName(), " ";
    echo $p->isOptional() ? "opt" : "req";
    echo $p->isVariadic() ? " variadic" : "";
    echo "\n";
}

$ref_capture = function() {
    $count = 0;
    return function() use (&$count) { return ++$count; };
};
$counter = $ref_capture();
echo $counter(), " ", $counter(), " ", $counter(), "\n";
