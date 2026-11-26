<?php
// a native writing a by-reference argument releases the variable's old
// value right there: its destructor runs inside the call, seeing null in
// an untyped variable and the new value in a typed one

// output stays buffered so headers_sent() writes an empty file name
ob_start();

class D {
    public function __construct(public string $name) {}
    public function __destruct() {
        global $seen;
        echo "destruct {$this->name}, variable is ", var_export($seen(), true), "\n";
        debug_print_backtrace();
    }
}

$x = new D("x");
$seen = fn () => $GLOBALS['x'];
headers_sent($x);
echo "after headers_sent\n";

function local() {
    global $seen;
    $y = new D("y");
    $seen = fn () => null;
    headers_sent($y, $line);
    echo "after headers_sent in a function: ", var_export($y, true), "\n";
}
local();

class T {
    public D|string $p;
}
$t = new T;
$t->p = new D("typed");
$seen = fn () => $GLOBALS['t']->p;
headers_sent($t->p);
var_dump($t->p);

// the value a WeakMap entry keyed by the old value held goes with it
$map = new WeakMap;
$key = new stdClass;
$map[$key] = new D("weak value");
$seen = fn () => $GLOBALS['key'];
headers_sent($key);
var_dump(count($map));

// an exception the destructor throws reaches the code after the call
class Thrower {
    public function __destruct() {
        throw new Exception("from destructor");
    }
}
$z = new Thrower;
try {
    headers_sent($z, $line);
    echo "not reached\n";
} catch (Exception $e) {
    echo $e->getMessage(), "\n", $e->getTraceAsString(), "\n";
}
var_dump($z);
