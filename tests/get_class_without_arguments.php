<?php
// get_class() without arguments names the calling scope's class, with php
// 8.3's deprecation, and is an Error outside a class
error_reporting(E_ALL);

class Base {
    static function fromStatic() {
        var_dump(get_class());
    }
    function fromMethod() {
        var_dump(get_class());
    }
}
class Child extends Base {
}
Child::fromStatic();
(new Child)->fromMethod();
try {
    get_class();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$bound = Closure::bind(function () {
    return get_class();
}, null, Base::class);
var_dump($bound());
