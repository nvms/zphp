<?php
// php 8.6 deprecates returning a value from a constructor or destructor, a
// generator constructor or destructor, returning from a finally block, and a
// nullable __debugInfo() return type; all while compiling
set_error_handler(function ($no, $msg, $file, $line) {
    echo "[$no] $msg (line $line)\n";
    return true;
});
$code = <<<'PHP'
class A {
    public function __construct() {
        if (false) return 1;
        return;
    }
    public function __destruct() { return null; }
    public function other() { return 1; }
}
class G {
    public function __construct() { yield 1; }
    public function __DESTRUCT() { yield; }
}
class D {
    public function __debugInfo(): ?array { return null; }
}
class E {
    public function __debugInfo(): array|null { return []; }
}
function f() {
    try {
        return 1;
    } finally {
        echo "finally\n";
        return 2;
    }
}
function g() {
    foreach ([1, 2] as $x) {
        try {
            if ($x == 1) continue;
            return $x;
        } finally {
            if ($x == 2) return 10;
        }
    }
}
function h() {
    try {
    } finally {
        $c = function () { return 3; };
        echo $c(), "\n";
    }
}
class Closures {
    public function __construct() {
        $f = fn() => 1;
        $g = function () { return 2; };
        echo $f() + $g(), "\n";
    }
}
var_dump(f(), g());
h();
new Closures;
var_dump(new D);
PHP;
eval($code);
