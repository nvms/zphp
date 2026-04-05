<?php

// base64_decode strict mode
echo var_export(base64_decode("SGVsbG8=", true), true) . "\n";
echo var_export(base64_decode("SGVs!!!bG8=", true), true) . "\n";
echo var_export(base64_decode("SGVsbG8=", false), true) . "\n";

// class_exists('stdClass')
echo var_export(class_exists('stdClass'), true) . "\n";

// property_exists with string class name
class TestProp {
    public $name = 'test';
    public $age = 0;
}
echo var_export(property_exists('TestProp', 'name'), true) . "\n";
echo var_export(property_exists('TestProp', 'missing'), true) . "\n";

// settype to object
$arr = ['name' => 'test', 'age' => 30];
settype($arr, 'object');
echo get_class($arr) . "\n";
echo $arr->name . "\n";
echo $arr->age . "\n";

// print_r with object properties
$obj = new stdClass();
$obj->name = 'Alice';
$obj->age = 30;
echo print_r($obj, true);

// strtotime EU date
echo date('Y-m-d', strtotime('15.03.2025')) . "\n";

// sprintf argument swapping
echo sprintf('%2$s %1$s', 'world', 'hello') . "\n";

// DateInterval months and days
$d1 = new DateTime('2025-01-15');
$d2 = new DateTime('2025-04-20');
$diff = $d1->diff($d2);
echo $diff->m . "\n";
echo $diff->d . "\n";
