<?php
// empty() on an SplFixedArray subclass with its own offsetExists() asks it alone
$f = new SplFixedArray(3); $f[0] = 0; $f[1] = "x";
var_dump(empty($f[0]), empty($f[1]), empty($f[2]), isset($f[0]));
class A extends SplFixedArray { function offsetExists($i): bool { echo "exists $i\n"; return parent::offsetExists($i); } function offsetGet($i): mixed { echo "get $i\n"; return parent::offsetGet($i); } }
$a = new A(3); $a[0] = 0;
var_dump(empty($a[0]), empty($a[2]), isset($a[0]));
