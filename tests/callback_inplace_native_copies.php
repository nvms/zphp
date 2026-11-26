<?php
// a native that changes its array argument in place, called through a
// callback with a value, changes a copy: the caller's array stays as it was.
// array_multisort prefers a reference and takes every array that way

set_error_handler(function ($errno, $message) {
    echo "warning: $message\n";
    return true;
});

$args = [[3, 2, 1]];
call_user_func_array('array_multisort', $args);
echo implode(',', $args[0]), "\n";

$args = [[3, 2, 1], ['c', 'b', 'a']];
var_dump(call_user_func_array('array_multisort', $args));
echo implode(',', $args[0]), ' ', implode(',', $args[1]), "\n";

$args = [[3, 2, 1]];
call_user_func_array('sort', $args);
echo implode(',', $args[0]), "\n";

$array = [3, 2, 1];
$other = ['z', 'y', 'x'];
call_user_func('array_multisort', $array, $other);
echo implode(',', $array), ' ', implode(',', $other), "\n";

// a reference in the argument array is passed as that reference
$data = [3, 2, 1];
$args = [&$data];
call_user_func_array('array_multisort', $args);
echo implode(',', $data), "\n";

$data = [5, 4];
$args = [&$data];
call_user_func_array('sort', $args);
echo implode(',', $data), "\n";

// a direct call still sorts the variable
$array = [3, 2, 1];
$copy = $array;
array_multisort($array);
echo implode(',', $array), ' ', implode(',', $copy), "\n";

