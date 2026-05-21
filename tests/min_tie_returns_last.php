<?php
// regression: when min() arguments compare equal it returns the LAST equal
// value (PHP replaces on <=), while max() returns the FIRST. zphp's min
// previously kept the first equal value.
var_dump(min(0, false));        // false
var_dump(min(false, 0));        // 0
var_dump(min(0, 0.0));          // 0.0
var_dump(min(0.0, 0));          // 0
var_dump(min(null, false));     // false
var_dump(min(false, null));     // null
var_dump(min(0, null));         // null
var_dump(min(2, 2));            // 2

// max keeps the first equal value
var_dump(max(0, false));        // 0
var_dump(max(false, 0));        // false
var_dump(max(1, true));         // 1
var_dump(max(true, 1));         // true

// distinct values are unaffected
echo min(3, 1, 2), ' ', max(3, 1, 2), "\n";
echo min([5, 2, 8, 1]), ' ', max([5, 2, 8, 1]), "\n";
echo min(-5, -1, -10), ' ', max(-5, -1, -10), "\n";
echo min(1.5, 2.5), ' ', max(1.5, 2.5), "\n";
echo min('apple', 'banana'), ' ', max('apple', 'banana'), "\n";

// array form, tie keeps the later element
var_dump(min([0, false]));      // false
var_dump(min([false, 0]));      // 0
var_dump(min([3, 1, 1, 2]));    // 1
