<?php
// array_column converts index keys as array_set_zval_key does
$rows = [["a" => 7.38, "v" => 1], ["a" => null, "v" => 2], ["a" => STDERR, "v" => 3], ["a" => true, "v" => 4], ["a" => "05", "v" => 5]];
var_dump(array_column($rows, "v", "a"));
try { array_column([["a" => []]], null, "a"); } catch (Error $e) { echo $e->getMessage(), "\n"; }
