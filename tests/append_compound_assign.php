<?php
// `$c[] op= v` starts from null on an array, from offsetGet(null) on an
// ArrayAccess object (then offsetSet(null, result)), and refuses strings
class Logged implements ArrayAccess {
    public array $log = [];
    function offsetExists($o): bool { $this->log[] = "exists"; return false; }
    function offsetGet($o): mixed { $this->log[] = "get " . var_export($o, true); return 100; }
    function offsetSet($o, $v): void { $this->log[] = "set " . var_export($o, true) . " " . var_export($v, true); }
    function offsetUnset($o): void { $this->log[] = "unset"; }
}
$c = new Logged;
var_dump($c[] += 5);
var_dump($c[] .= "x");
print_r($c->log);

$a = [1];
var_dump($a[] += 5, $a[] .= "s", $a);

function rhs() { echo "rhs\n"; return 1; }
$c2 = new Logged;
$c2[] -= rhs();
print_r($c2->log);

$str = "abc";
try {
    $str[] += 1;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$o = new stdClass;
try {
    $o[] += 1;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$n = null;
$n[] += 2;
var_dump($n);
