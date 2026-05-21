<?php
// regression: reading a typed property before it is written is a fatal Error
// ("must not be accessed before initialization") in PHP. zphp returned null.
// `??` / `??=` / isset() use isset-semantics and must NOT throw there.

class Box {
    public int $a;
    public string $s;
    public float $f;
    public array $arr;
    public stdClass $obj;
    public int $withDefault = 5;
    public $untyped;
}

$b = new Box;

// a typed property with a default, and an untyped property, read fine
var_dump($b->withDefault);
var_dump($b->untyped);

// reading an uninitialized typed property throws a catchable Error
try { $v = $b->a; echo "a: no error\n"; } catch (Error $e) { echo "a: ", $e->getMessage(), "\n"; }
try { $v = $b->s; echo "s: no error\n"; } catch (Error $e) { echo "s: ", $e->getMessage(), "\n"; }
try { $v = $b->f; echo "f: no error\n"; } catch (Error $e) { echo "f: ", $e->getMessage(), "\n"; }
try { $v = $b->arr; echo "arr: no error\n"; } catch (Error $e) { echo "arr: ", $e->getMessage(), "\n"; }
try { $v = $b->obj; echo "obj: no error\n"; } catch (Error $e) { echo "obj: ", $e->getMessage(), "\n"; }

// isset() on an uninitialized typed property is false - no error
var_dump(isset($b->a));

// `??` reads with isset-semantics: an uninitialized typed property routes to
// the right-hand side instead of throwing
echo $b->a ?? 'fallback-a', "\n";
echo $b->withDefault ?? 'unused', "\n";

// `??=` initializes an uninitialized typed property
$b->a ??= 42;
var_dump($b->a);
$b->a ??= 999;        // already set - left unchanged
var_dump($b->a);

// after a normal write the property reads fine
$b->s = "hello";
echo $b->s, "\n";

// repeated reads exercise the inline-cache path
for ($i = 0; $i < 4; $i++) echo $b->a;
echo "\n";

// explicitly unset returns a typed property to the uninitialized state
unset($b->s);
try { echo $b->s; } catch (Error $e) { echo "after unset: ", $e->getMessage(), "\n"; }
echo $b->s ?? 'unset-fallback', "\n";

// inheritance: a parent's uninitialized typed property
class Base { public int $x; }
class Derived extends Base { public int $y; }
$d = new Derived;
try { echo $d->x; } catch (Error $e) { echo "inherited x uninitialized\n"; }
$d->x = 1;
$d->y = 2;
echo $d->x + $d->y, "\n";

// a constructor that initializes the property - no error afterwards
class Ready {
    public int $n;
    public function __construct() { $this->n = 7; }
}
echo (new Ready)->n, "\n";

// promoted constructor parameter is always initialized
class Promoted {
    public function __construct(public int $val) {}
}
echo (new Promoted(123))->val, "\n";

// the Carbon pattern: a lazy getter using `??=` on a typed property
class Factory {
    private string $translator;
    public function getTranslator(): string {
        return $this->translator ??= 'default-translator';
    }
}
$fac = new Factory;
echo $fac->getTranslator(), "\n";
echo $fac->getTranslator(), "\n";

// a falsy-but-not-null value reads fine (0, false, "", 0.0 are initialized)
class Falsy { public int $z; public bool $bf; public string $es; }
$fl = new Falsy;
$fl->z = 0; $fl->bf = false; $fl->es = "";
var_dump($fl->z, $fl->bf, $fl->es);

// chained ?? across uninitialized typed properties
$d2 = new Derived;
echo $d2->x ?? $d2->y ?? 'both-uninit', "\n";
