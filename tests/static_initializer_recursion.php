<?php
// a static variable's initializer that initializes the variable itself
// (through recursion) leaves that value in place

function foo($i) {
    static $a = $i <= 10 ? foo($i + 1) : "Done $i";
    var_dump($a);
    return $i;
}
foo(0);
foo(5);

function counter() {
    static $n = str_repeat('n', 2);
    $n .= '+';
    return $n;
}
echo counter(), "\n", counter(), "\n";

class K {
    static function make($depth) {
        static $made = $depth < 3 ? self::make($depth + 1) : ['depth' => $depth];
        return $made;
    }
}
var_dump(K::make(0));
