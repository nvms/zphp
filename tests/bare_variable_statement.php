<?php
// a statement that is only a variable reads nothing, so it doesn't warn,
// while a variable variable is fetched and does
$a;
($a);
$n = "b";
$$n;
function f() {
    $c;
    echo "f\n";
}
f();
function g() {
    try {
        $this;
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
g();
