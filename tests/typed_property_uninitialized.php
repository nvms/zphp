<?php
// a typed property declared without a default is uninitialized, not null,
// until something is assigned to it, whatever its type

class Box
{
    public ?int $n;
    public mixed $m;
    public int|string|null $u;
    public ?Box $next;
    public $untyped;
    public ?int $set = null;

    public function __construct(public ?string $promoted = null) {}
}

function attempt(callable $f): void
{
    try {
        var_dump($f());
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$b = new Box;
var_dump($b);
print_r($b);
echo "\n";
var_export($b);
echo "\n";
var_dump((array) $b, get_object_vars($b), json_encode($b), serialize($b));
foreach ($b as $k => $v) echo "$k => ", var_export($v, true), "\n";
var_dump(isset($b->n), $b->n ?? "default", property_exists($b, 'n'), empty($b->m));
attempt(fn () => $b->n);
attempt(fn () => $b->m);
attempt(fn () => $b->next?->n);
$rp = new ReflectionProperty(Box::class, 'n');
var_dump($rp->isInitialized($b));
$c = clone $b;
var_dump($c == $b);
$b->n = null;
$b->m = null;
var_dump($b->n, $b->m, $rp->isInitialized($b));
unset($b->n);
attempt(fn () => $b->n);
$r = &$b->u;
var_dump($b->u);
attempt(function () { $o = new class { public int $i; }; $x = &$o->i; });
var_dump((new ReflectionClass(Box::class))->getDefaultProperties());
var_dump(unserialize(serialize(new Box)));

class Magic
{
    public int $typed;
    public function __get($name) { echo "__get($name)\n"; return "12"; }
}
$m = new Magic;
attempt(fn () => $m->typed);
unset($m->typed);
attempt(fn () => $m->typed);
