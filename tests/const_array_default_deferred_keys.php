<?php
// elements without a key after a key a constant decides take the next free
// key once the constant is known

const FOO = 5;
const NEG = -3;

function t($x = [FOO => 1, 'x', 3 => 'y', 'z']) { var_dump($x); }
t();

function n($x = [NEG => 'a', 'b', 'c']) { var_dump($x); }
n();

class K {
    const BASE = 10;
    public $p = [FOO => 1, 'x'];
    const C = [self::BASE => 'a', 'b', 'k' => 'c', 'd'];
    public static $s = ['a', FOO => 'b', 'c'];
}
var_dump((new K)->p, K::C, K::$s);

function big($x = [PHP_INT_MAX => 42, "foo"]) { var_dump($x); }
try {
    big();
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
