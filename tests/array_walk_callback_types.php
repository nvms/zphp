<?php
// a callback that takes references still gets its parameter types checked
// and coerced when internal code calls it
class foo {}
function typehint(foo $a) { echo "typehint called\n"; }
function typehint_ref(foo &$a) { echo "typehint_ref called\n"; }
function int_ref(int &$v, $k) { var_dump($v); $v++; }
function str_val(string $v) { var_dump($v); }
foreach (['typehint', 'typehint_ref'] as $f) {
    $a = [new foo, 1];
    try {
        array_walk($a, $f);
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}
$nums = ["1", "2", 3.0];
array_walk($nums, 'int_ref');
var_dump($nums);
$vals = [1, 2.5, true];
array_walk($vals, 'str_val');
try {
    $bad = ["x"];
    array_walk($bad, 'int_ref');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
