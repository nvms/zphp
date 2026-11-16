<?php
// binding a static variable releases what the local variable held before,
// at once

class Noisy {
    public function __construct(public string $name) {}
    public function __destruct() {
        echo "destruct {$this->name}\n";
    }
}

function bar() {
    echo "bar() called\n";
    return 42;
}

function foo(bool $make) {
    if ($make) {
        $a = new Noisy('local');
    }
    static $a = bar();
    echo "after static\n";
    var_dump($a);
}
foo(true);
foo(false);
foo(true);

class Thrower {
    public function __destruct() {
        throw new Exception('__destruct() called');
    }
}
function baz(bool $throw) {
    if ($throw) {
        $b = new Thrower();
    }
    static $b = 7;
    var_dump($b);
}
try {
    baz(true);
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
baz(false);
