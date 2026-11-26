<?php
// a dimension write that would turn a typed property (or a reference one
// holds) into an array needs a type that allows arrays

class Foo {
    public ?string $p;
    public ?iterable $i;
    public mixed $m;
    public ?int $n = null;
    public string|false $f = false;
    public ?array $a = null;
    public static ?string $s;
    public static ?array $sa;
    public static ?int $sn = null;
}

function attempt(string $label, callable $fn) {
    try {
        $fn();
        echo "$label: ok\n";
    } catch (Throwable $e) {
        echo "$label: ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$o = new Foo;
attempt('i[]', function () use ($o) { $o->i[] = 1; });
attempt('m[]', function () use ($o) { $o->m['k'] = 1; });
attempt('p[]', function () use ($o) { $o->p[] = 'x'; });
attempt('p read', function () use ($o) { var_dump($o->p); });
attempt('p[k]', function () use ($o) { $o->p['k'] = 'x'; });
attempt('p[k][]', function () use ($o) { $o->p['k'][] = 'x'; });
attempt('n[]', function () use ($o) { $o->n[] = 1; });
attempt('n[k] .=', function () use ($o) { $o->n['k'] ??= 1; });
attempt('f[]', function () use ($o) { $o->f[] = 1; });
attempt('a[]', function () use ($o) { $o->a[] = 1; });
var_dump($o->n, $o->f, $o->a);

attempt('s[k][]', function () { Foo::$s['k'][] = 1; });
attempt('s read', function () { var_dump(Foo::$s); });
attempt('sn[]', function () { Foo::$sn[] = 1; });
attempt('sa[]', function () { Foo::$sa[] = 1; });
var_dump(Foo::$sn, Foo::$sa);

$o->p = null;
$ref = &$o->p;
attempt('ref[]', function () use (&$ref) { $ref[] = 'x'; });
attempt('ref[k][]', function () use (&$ref) { $ref['k'][] = 'x'; });
attempt('o->p[] via ref', function () use ($o) { $o->p[] = 'x'; });
var_dump($ref);

$sref = &Foo::$sn;
attempt('sref[]', function () use (&$sref) { $sref[] = 1; });
var_dump($sref);

$aref = &$o->a;
$aref[] = 'ok';
var_dump($o->a);

// an untyped property still becomes an array
class Bar { public $u; }
$b = new Bar;
$b->u[] = 1;
var_dump($b->u);

// references in a function's locals and at the top level
function viaLocal(Foo $o) {
    $r = &$o->n;
    attempt('local r[k]', function () use (&$r) { $r['k'] = 1; });
    try { $r['k'] = 1; } catch (TypeError $e) { echo "local: ", $e->getMessage(), "\n"; }
    try { $r[] = 1; } catch (TypeError $e) { echo "local: ", $e->getMessage(), "\n"; }
    try { $r['a']['b'] = 1; } catch (TypeError $e) { echo "local: ", $e->getMessage(), "\n"; }
    var_dump($r);
}
viaLocal(new Foo);
$top = new Foo;
$tr = &$top->n;
try { $tr['k'] = 1; } catch (TypeError $e) { echo "top: ", $e->getMessage(), "\n"; }
try { $tr[] = 1; } catch (TypeError $e) { echo "top: ", $e->getMessage(), "\n"; }
var_dump($tr);
