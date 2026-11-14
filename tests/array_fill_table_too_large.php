<?php
// array_fill refuses a table php's hash can't size before allocating it
var_dump(count(array_fill(5, 3, 'x')));
var_dump(array_fill(-3, 2, 0));
array_fill(1, 1024 * 1024 * 1024, 'x');
echo "not reached\n";
