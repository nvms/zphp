<?php
// array_walk() over an object hands each property to the callback as a
// reference to the property itself, typed by its declaration; a lazy object
// initializes first and a proxy's instance is walked

class C {
    public int $a = 1;
    protected string $b = 'b';
    private ?array $c = null;
    public $d = 'd';
    public function dump() {
        var_dump($this->a, $this->b, $this->c, $this->d);
    }
}

function setter(&$value, $key) {
    try {
        $value = new stdClass;
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
    $value = match (true) {
        is_int($value) => $value + 10,
        is_string($value) => $value . '!',
        default => [bin2hex($key)],
    };
}

class Walker {
    public function visit(&$value, $key, $suffix) {
        if (is_int($value)) $value *= 2;
        echo "visit ", bin2hex($key), " $suffix\n";
    }
}

$o = new C;
@array_walk($o, 'setter');
$o->dump();
var_dump($o);

@array_walk($o, [new Walker, 'visit'], 'x');
$o->dump();

// a by-value callback changes nothing
@array_walk($o, function ($value, $key) {
    $value = 'changed';
});
$o->dump();

// a reference held elsewhere keeps its own type checks
$r = &$o->a;
@array_walk($o, function (&$value) {
    if (is_int($value)) $value = '5';
});
var_dump($r);

$rc = new ReflectionClass(C::class);
$ghost = $rc->newLazyGhost(function ($g) {
    echo "ghost init\n";
});
@array_walk($ghost, function (&$value, $key) {
    if (is_int($value)) $value = 7;
});
var_dump($rc->isUninitializedLazyObject($ghost));
$ghost->dump();

$proxy = $rc->newLazyProxy(function () {
    echo "proxy init\n";
    return new C;
});
@array_walk($proxy, function (&$value) {
    try {
        $value = 'string';
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
});
var_dump($rc->isUninitializedLazyObject($proxy));
$proxy->dump();
var_dump(get_object_vars($proxy));
