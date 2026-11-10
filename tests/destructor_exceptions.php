<?php
// an exception thrown by a destructor is raised where the object was
// released, taking an exception already in flight as its previous; the
// operands an exception unwinds are released before the catch runs; the
// objects left at the end are destructed after the shutdown functions

register_shutdown_function(function () { echo "shutdown function\n"; });
$survivor = new class { function __destruct() { echo "survivor destructed\n"; } };

class Throws {
    function __construct(public $name) {}
    function __destruct() {
        echo "{$this->name} destructed\n";
        throw new Exception("from {$this->name}");
    }
}
class Noisy {
    function __construct(public $n) {}
    function __destruct() { echo "noisy {$this->n} gone\n"; }
}

function unsets() {
    $t = new Throws("unset");
    unset($t);
    echo "not reached\n";
}
try {
    unsets();
} catch (Exception $e) {
    echo "caught ", $e->getMessage(), "\n";
}

function unwinds() {
    $t = new Throws("local");
    throw new Exception("original");
}
try {
    unwinds();
} catch (Exception $e) {
    echo "caught ", $e->getMessage(), ", previous ", $e->getPrevious()?->getMessage(), "\n";
}

function sink(...$args) {}
function fails() {
    throw new Exception("argument failed");
}
try {
    sink(new Noisy(1), fails());
} catch (Exception $e) {
    echo "caught ", $e->getMessage(), "\n";
}
function nested() {
    return sink(new Noisy(2), fails());
}
try {
    nested();
} catch (Exception $e) {
    echo "caught ", $e->getMessage(), "\n";
}

try {
    $t = new Throws("reassigned");
    $t = null;
    echo "not reached\n";
} catch (Exception $e) {
    echo "caught ", $e->getMessage(), "\n";
}

try {
    throw new Exception("e");
} catch (Exception $e) {
    try {
        throw new RuntimeException("rethrown");
    } finally {
        echo "finally\n";
    }
}
