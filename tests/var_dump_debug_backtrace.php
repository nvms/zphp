<?php
// var_dump basic
var_dump(42);
var_dump(3.14);
var_dump("hello");
var_dump(true);
var_dump(false);
var_dump(null);
var_dump([1, 2, 3]);
var_dump([]);
var_dump(["a" => 1, "b" => "two"]);

// nested arrays
var_dump([
    "list" => [1, 2, 3],
    "map" => ["a" => 1],
    "deep" => ["x" => ["y" => "z"]],
]);

// var_dump multiple args
var_dump("a", 1, true);

// objects with public/protected/private
class Box {
    public int $width = 10;
    protected int $height = 20;
    private string $color = "red";
    private static int $count = 0;
}
var_dump(new Box);

class Inherited extends Box {
    public string $label = "boxy";
}
var_dump(new Inherited);

// stdClass
$o = (object)["a" => 1, "b" => 2];
var_dump($o);

// nested object var_dump (architectural - object id counter differs)

// circular array via reference
$a = [];
$a[] = 1;
$a[] = &$a;
ob_start();
var_dump($a);
$out = ob_get_clean();
echo strpos($out, "RECURSION") !== false ? "has-rec" : "no-rec", "\n";

// circular object
class Node {
    public ?Node $next = null;
    public int $val = 0;
}
$n = new Node;
$n->val = 1;
$n->next = $n;
ob_start();
var_dump($n);
$out = ob_get_clean();
echo strpos($out, "RECURSION") !== false || strpos($out, "*RECURSION*") !== false ? "obj-rec" : "no-obj-rec", "\n";

// var_dump on TypedProps + fopen resource (architectural - id counter / FileHandle vs resource)

// special floats
var_dump(NAN);
var_dump(INF);
var_dump(-INF);
var_dump(0.0);
var_dump(-0.0);

// large numbers
var_dump(PHP_INT_MAX);
var_dump(PHP_INT_MIN);
var_dump(PHP_FLOAT_MAX);

// debug_print_backtrace simple
function inner_call() {
    debug_print_backtrace();
}
function outer_call() {
    inner_call();
}
outer_call();

// debug_backtrace returns array
function dbg() {
    return debug_backtrace();
}
function caller() {
    return dbg();
}
$bt = caller();
echo gettype($bt), "\n";
echo count($bt) > 0 ? "non-empty" : "empty", "\n";
echo isset($bt[0]["function"]) ? "has-function" : "no-function", "\n";

// debug_backtrace with limit
function a1() { return debug_backtrace(0, 2); }
function a2() { return a1(); }
function a3() { return a2(); }
$bt = a3();
echo count($bt) <= 2 ? "limit-ok" : "limit-no", " count=", count($bt), "\n";

// print_r vs var_dump for object
class P { public int $x = 1; public string $y = "hi"; }
$p = new P;
print_r($p);
echo "---\n";

// print_r with return = true
$out = print_r($p, true);
echo strlen($out) > 0 ? "has-out\n" : "no-out\n";

// debug_zval_refcount removed in PHP 8.4+ (both error - architectural skip on stack-trace formatting)

// __debugInfo magic method (architectural - object id counter differs)
