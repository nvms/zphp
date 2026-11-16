<?php
// `$c[]++` / `$c[]--` and the prefix forms fetch the appended element for
// read-write first: an array appends the stepped null, an ArrayAccess
// object steps what offsetGet(null) returns without writing it back, and a
// string or a scalar is an Error before the step
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });

class A implements ArrayAccess {
    public $calls = [];
    function offsetGet($o): mixed { $this->calls[] = "get " . var_export($o, true); return 5; }
    function offsetSet($o, $v): void { $this->calls[] = "set"; }
    function offsetExists($o): bool { return true; }
    function offsetUnset($o): void {}
}

$a = new A;
var_dump($a[]++);
var_dump(++$a[]);
var_dump($a[]--);
var_dump(--$a[]);
print_r($a->calls);

$x = null;
var_dump($x[]--);
var_dump(--$x[]);
var_dump($x[]++);
var_dump(++$x[]);
var_dump($x);

$arr = [1];
$copy = $arr;
$arr[]++;
var_dump($arr, $copy);

$n = ['k' => [1]];
$n['k'][]++;
$n['new'][]++;
var_dump($n);

foreach (['md5(0)[]--;', '$s = "str"; $s[]++;', '$i = 5; $i[]++;', '$o = new stdClass; $o[]++;'] as $code) {
    try {
        eval($code);
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$full = [PHP_INT_MAX => 1];
try {
    $full[]++;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

$w = [];
$w["x"][] .= "a";
$undefined_root[] .= "b";
var_dump($w, $undefined_root);
