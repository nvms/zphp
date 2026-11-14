<?php
// isset, empty and eval are language constructs, not functions
foreach (['isset', 'empty', 'eval', 'ISSET', 'Eval', 'strlen'] as $f) {
    echo $f, ": ", var_export(function_exists($f), true), " ", var_export(is_callable($f), true), "\n";
    try {
        var_dump(array_map($f, ['a']));
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
try {
    new ReflectionFunction('isset');
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
var_dump(in_array('isset', get_defined_functions()['internal']));
$x = 1;
var_dump(isset($x), empty($x), eval('return 2;'));
