<?php
// lazy objects: a write runs __set or a set hook before the object is
// initialized; a reference to an undeclared property asks __get first; a
// proxy whose factory throws keeps what the factory wrote, a ghost doesn't

#[AllowDynamicProperties]
class WithSet {
    public $_;
    public function __set($name, $value) {
        var_dump(__METHOD__);
        $this->$name = $value * 2;
    }
}
$rc = new ReflectionClass(WithSet::class);
$obj = $rc->newLazyProxy(function () {
    echo "init\n";
    return new WithSet;
});
$obj->prop = 1;
var_dump($obj->prop);

class WithHook {
    public $prop {
        set {
            echo "set\n";
            $this->prop = $value * 2;
        }
    }
}
$rc = new ReflectionClass(WithHook::class);
$obj = $rc->newLazyProxy(function () {
    echo "init\n";
    return new WithHook;
});
$obj->prop = 1;
var_dump($obj->prop);

$ghost = $rc->newLazyGhost(function ($o) {
    echo "ghost init\n";
});
$ghost->prop = 5;
var_dump($ghost->prop);

class RefGet {
    public $_;
    public function &__get($name) {
        echo "__get($name)\n";
        return $name;
    }
}
$proxy = (new ReflectionClass(RefGet::class))->newLazyProxy(function () {
    echo "init\n";
    return new RefGet();
});
$x = &$proxy->x;
var_dump($x);
var_dump((new ReflectionClass(RefGet::class))->isUninitializedLazyObject($proxy));

class C {
    public $a = 1;
    public int $b = 2;
    public int $c;
}
function test(string $name, object $obj) {
    $reflector = new ReflectionClass(C::class);
    echo "# $name\n";
    try {
        $reflector->initializeLazyObject($obj);
    } catch (Exception $e) {
        echo $e->getMessage(), "\n";
    }
    print_r($obj);
    echo "\n";
    var_dump($reflector->isUninitializedLazyObject($obj));
}
$reflector = new ReflectionClass(C::class);
test('Ghost', $reflector->newLazyGhost(function ($obj) {
    $obj->a = 3;
    $obj->b = 4;
    throw new Exception('ghost initializer exception');
}));
test('Proxy', $reflector->newLazyProxy(function ($obj) {
    $obj->a = 3;
    $obj->b = 4;
    throw new Exception('proxy initializer exception');
}));
