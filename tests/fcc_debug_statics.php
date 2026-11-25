<?php
// a Closure made from a function shows the function's static variables
function counter() {
    static $calls = 0;
    static $last;
    $calls++;
    $last = $calls * 2;
}
$f = counter(...);
var_dump($f);
counter();
counter();
var_dump($f);
print_r(counter(...));
echo "\n";
function plain() {}
var_dump(plain(...));
