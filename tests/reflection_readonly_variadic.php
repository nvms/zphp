<?php

// ReflectionClass::isReadOnly (PHP 8.2+)
readonly class Frozen {
    public function __construct(public string $tag) {}
}
class Mutable {
    public string $tag = '';
}

$rc = new ReflectionClass(Frozen::class);
echo ($rc->isReadOnly() ? "yes" : "no") . "\n";

$rm = new ReflectionClass(Mutable::class);
echo ($rm->isReadOnly() ? "yes" : "no") . "\n";

// variadic params are always optional in reflection
function withVariadic(int $required, int ...$rest): void {}
$rf = new ReflectionFunction('withVariadic');
foreach ($rf->getParameters() as $p) {
    echo $p->getName() . ":" . ($p->isOptional() ? "opt" : "req") . "/" .
         ($p->isVariadic() ? "var" : "-") . "\n";
}
