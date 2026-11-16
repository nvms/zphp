<?php
// X::__construct() on a class without a constructor has nothing to call,
// even with __callStatic; with one, it is an ordinary non-static call
class NoCtor {
    static function __callStatic($a, $b) { var_dump($a); }
}
class WithCtor {
    function __construct() { echo "WithCtor::__construct\n"; }
}
class Child extends WithCtor {
    function __construct() {
        parent::__construct();
        WithCtor::__construct();
    }
}
try {
    NoCtor::__construct();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    NoCtor::__CONSTRUCT(1, 2);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
NoCtor::other();
new Child();
try {
    WithCtor::__construct();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
