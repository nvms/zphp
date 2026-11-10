<?php
// php 8.2 deprecates "${name}" and "${expr}" interpolation at compile time
set_error_handler(function ($no, $msg, $file, $line) {
    echo "error $no on line $line: $msg\n";
    return true;
});
$name = "world";
$arr = ["k" => "v"];
$world = "dynamic";
var_dump(eval('return "hello ${name}";'));
var_dump(eval('return "item ${arr[\'k\']}";'));
var_dump(eval('return "var\n\n ${$name}";'));
var_dump(eval('return "fine {$name} $name";'));
