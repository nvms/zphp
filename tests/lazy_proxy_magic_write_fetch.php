<?php
// an initialized lazy proxy's write fetches and writes for a name its class
// doesn't declare run __get and __set on the proxy itself; while the
// instance's own __get runs for the name, the proxy reads the instance

class Foo {
    public $_;
    public function __get($name) {
        echo "__get($name) on ", $this === $GLOBALS['proxy'] ? "proxy" : "instance", "\n";
        return 1;
    }
    public function __set($name, $v) {
        echo "__set($name) on ", $this === $GLOBALS['proxy'] ? "proxy" : "instance", "\n";
    }
}

$rc = new ReflectionClass(Foo::class);
$proxy = $rc->newLazyProxy(function () {
    echo "init\n";
    return new Foo();
});
$real = $rc->initializeLazyObject($proxy);

var_dump($proxy->x);
$r = &$proxy->y;
$name = 'y2';
$r2 = &$proxy->{$name};
$proxy->z = 1;
$proxy->w .= 'a';
try {
    $proxy->v = &$r;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$r = 5;
$r2 = 6;
var_dump($proxy);

class Bar {
    public $_;
    public function &__get($name) {
        global $proxy2;
        echo "Bar::__get($name)\n";
        return $proxy2->{$name};
    }
}

$rc = new ReflectionClass(Bar::class);
$proxy2 = $rc->newLazyProxy(fn() => new Bar());
$real2 = $rc->initializeLazyObject($proxy2);
$a = &$real2->x;
var_dump($a);
$a = 1;
var_dump($real2);

class Baz {
    public $_;
    public function __get($name) {
        global $proxy3;
        echo "Baz::__get($name)\n";
        $proxy3->made = 1;
        $r = &$proxy3->made;
        $r = 2;
        try {
            $proxy3->other = &$r;
            echo "bound\n";
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
        return $proxy3->{$name};
    }
}
$rc = new ReflectionClass(Baz::class);
$proxy3 = $rc->newLazyProxy(fn() => new Baz());
$real3 = $rc->initializeLazyObject($proxy3);
var_dump($real3->q);
var_dump($real3);
