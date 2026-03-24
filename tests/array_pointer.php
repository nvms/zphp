<?php

$arr = [10, 20, 30, 40];

// current returns first element
echo current($arr) . "\n";

// next advances and returns
echo next($arr) . "\n";
echo next($arr) . "\n";

// current shows where we are
echo current($arr) . "\n";

// prev goes back
echo prev($arr) . "\n";

// reset goes to start
echo reset($arr) . "\n";

// end goes to last
echo end($arr) . "\n";

// key returns current key
reset($arr);
echo key($arr) . "\n";
next($arr);
echo key($arr) . "\n";

// associative array
$assoc = ["a" => 1, "b" => 2, "c" => 3];
echo current($assoc) . "\n";
echo key($assoc) . "\n";
next($assoc);
echo key($assoc) . "\n";
echo current($assoc) . "\n";
end($assoc);
echo key($assoc) . "\n";

// past end returns false
$small = [1];
next($small);
var_dump(current($small));

// sizeof alias
echo sizeof([1, 2, 3]) . "\n";
