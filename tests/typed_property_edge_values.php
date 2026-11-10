<?php
// typed properties holding closures from constant expressions, an anonymous
// class's self in errors, and references to lazy objects' properties

class WithClosure
{
    public Closure $c = static function () { return "called"; };
    public static Closure $s = static function () { return "static called"; };
}
$o = new WithClosure;
echo ($o->c)(), "\n", (WithClosure::$s)(), "\n";

$anon = new class {
    public self $me;
    public int|self $either = 0;
};
foreach (['me', 'either'] as $p) {
    try {
        $anon->$p = "x";
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}

class Pair
{
    public function __construct(public int $a, public int $b) {}
}
$reflector = new ReflectionClass(Pair::class);
$ghost = $reflector->newLazyGhost(function ($p) { $p->__construct(3, 4); });
$name = 'a';
$ref = &$ghost->$name;
var_dump($ref);
$proxy = $reflector->newLazyProxy(function () { return new Pair(5, 6); });
$first = 'a';
$second = 'b';
$proxy->$second = &$proxy->$first;
try {
    $proxy->$first = "nope";
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$proxy->$first = 9;
var_dump($proxy->b);
