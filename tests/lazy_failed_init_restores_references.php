<?php
// a failed initializer puts the properties back in the references they were
// bound to (typed again), and references the initializer made lose them

class C {
    public ?C $a;
    public ?C $b;
    public int $n = 0;
    public $c;
    public function __construct() {
        unset($this->b);
        global $made;
        $made = &$this->n;
        throw new Exception('initializer exception');
    }
}

function test(string $name, object $obj) {
    $reflector = new ReflectionClass(C::class);
    printf("# %s:\n", $name);
    $reflector->getProperty('a')->setRawValueWithoutLazyInitialization($obj, null);
    $refA = &$obj->a;
    $reflector->getProperty('b')->setRawValueWithoutLazyInitialization($obj, null);
    $refB = &$obj->b;
    try {
        var_dump($obj->c);
    } catch (Exception $e) {
        echo $e->getMessage(), "\n";
    }
    var_dump($obj);
    foreach (['refA', 'refB'] as $var) {
        try {
            $$var = 1;
            echo "$var: assigned\n";
        } catch (TypeError $e) {
            echo $e->getMessage(), "\n";
        }
    }
    global $made;
    $made = "not an int";
    var_dump($made);
    unset($obj->a, $obj->b);
    $refA = 1;
    $refB = 2;
    var_dump($refA, $refB);
}

$reflector = new ReflectionClass(C::class);
test('Ghost', $reflector->newLazyGhost(function ($obj) {
    $obj->__construct();
}));
test('Proxy', $reflector->newLazyProxy(function ($obj) {
    return new C();
}));
