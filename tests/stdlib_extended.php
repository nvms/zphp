<?php

// compact
$name = "Alice";
$age = 30;
$city = "NYC";
$result = compact("name", "age", "city");
echo $result["name"] . "\n";
echo $result["age"] . "\n";
echo $result["city"] . "\n";

// extract
$data = ["color" => "blue", "size" => "large", "weight" => 10];
extract($data);
echo $color . "\n";
echo $size . "\n";
echo $weight . "\n";

// var_export
var_export(null);
echo "\n";
var_export(true);
echo "\n";
var_export(false);
echo "\n";
var_export(42);
echo "\n";
var_export("hello");
echo "\n";
var_export("it's");
echo "\n";

// var_export with return
$str = var_export([1, 2, 3], true);
echo $str . "\n";

// ob_start / ob_get_clean
ob_start();
echo "buffered content";
$captured = ob_get_clean();
echo "captured: " . $captured . "\n";

// nested output buffering
ob_start();
echo "outer ";
ob_start();
echo "inner";
$inner = ob_get_clean();
echo $inner;
$outer = ob_get_clean();
echo $outer . "\n";

// ob_get_level
echo ob_get_level() . "\n";
ob_start();
$level = ob_get_level();
ob_end_clean();
echo $level . "\n";
echo ob_get_level() . "\n";
