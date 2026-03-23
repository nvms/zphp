<?php

// is_object
$obj = new stdClass();
echo var_export(is_object($obj), true) . "\n";
echo var_export(is_object("string"), true) . "\n";
echo var_export(is_object(42), true) . "\n";

// get_class
class MyClass {}
$m = new MyClass();
echo get_class($m) . "\n";

// class_exists
echo var_export(class_exists("MyClass"), true) . "\n";
echo var_export(class_exists("NonExistent"), true) . "\n";

// method_exists
class Foo {
    public function bar() { return 1; }
}
$foo = new Foo();
echo var_export(method_exists($foo, "bar"), true) . "\n";
echo var_export(method_exists($foo, "baz"), true) . "\n";
echo var_export(method_exists("Foo", "bar"), true) . "\n";

// property_exists
class PropTest {
    public $name = "test";
}
$pt = new PropTest();
echo var_export(property_exists($pt, "name"), true) . "\n";
echo var_export(property_exists($pt, "age"), true) . "\n";

// is_callable
function my_func() { return 1; }
echo var_export(is_callable("my_func"), true) . "\n";
echo var_export(is_callable("nonexistent_func"), true) . "\n";
echo var_export(is_callable("strlen"), true) . "\n";

// function_exists
echo var_export(function_exists("strlen"), true) . "\n";
echo var_export(function_exists("my_func"), true) . "\n";
echo var_export(function_exists("nope"), true) . "\n";

// call_user_func
function double($x) { return $x * 2; }
echo call_user_func("double", 21) . "\n";
echo call_user_func("strtoupper", "hello") . "\n";

// call_user_func_array
echo call_user_func_array("double", [10]) . "\n";
echo call_user_func_array("implode", [", ", ["a", "b", "c"]]) . "\n";
