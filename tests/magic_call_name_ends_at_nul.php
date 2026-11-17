<?php
// __call and __callStatic get the method name up to its first NUL
class A {
    public function __call($name, $args) { var_dump($name, $args); }
    public static function __callStatic($name, $args) { var_dump($name, $args); }
}
$a = new A;
$cls = 'A';
foreach (["\0", "ab\0cd", "plain", ""] as $name) {
    $a->$name(1);
    $cls::$name(2);
    A::$name(3);
    call_user_func([$a, $name], 4);
    call_user_func([$cls, $name], 5);
    call_user_func("A::$name", 6);
}
