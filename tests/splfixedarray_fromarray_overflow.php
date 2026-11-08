<?php
// a PHP_INT_MAX key would need a size past the largest integer
foreach ([[PHP_INT_MAX => 'foo'], [0 => 'a', PHP_INT_MAX => 'b']] as $a) {
    try {
        SplFixedArray::fromArray($a);
    } catch (Exception $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
var_dump(SplFixedArray::fromArray([PHP_INT_MAX => 'foo'], false)->toArray());
var_dump(SplFixedArray::fromArray([3 => 'x'])->toArray());
try { SplFixedArray::fromArray([-1 => 1]); } catch (Exception $e) { echo $e->getMessage(), "\n"; }
