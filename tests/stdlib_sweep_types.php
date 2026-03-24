<?php
// comprehensive type/utility function sweep

// type checking
echo var_export(is_string("hello"), true) . "\n";
echo var_export(is_int(42), true) . "\n";
echo var_export(is_float(3.14), true) . "\n";
echo var_export(is_bool(true), true) . "\n";
echo var_export(is_null(null), true) . "\n";
echo var_export(is_array([]), true) . "\n";
echo var_export(is_numeric("42"), true) . "\n";
echo var_export(is_numeric("3.14"), true) . "\n";
echo var_export(is_numeric("abc"), true) . "\n";
echo var_export(is_numeric("-5"), true) . "\n";

// type coercion
echo intval("42abc") . "\n";
echo intval("0xff", 16) . "\n";
echo floatval("3.14abc") . "\n";
echo strval(42) . "\n";
echo boolval("") . "\n";
echo boolval("hello") . "\n";

// gettype
echo gettype(42) . "\n";
echo gettype(3.14) . "\n";
echo gettype("hi") . "\n";
echo gettype(true) . "\n";
echo gettype(null) . "\n";
echo gettype([]) . "\n";

// isset/empty
$a = 42;
$b = null;
$c = "";
$d = 0;
$e = [];
echo var_export(isset($a), true) . "\n";
echo var_export(isset($b), true) . "\n";
echo var_export(empty($c), true) . "\n";
echo var_export(empty($d), true) . "\n";
echo var_export(empty($e), true) . "\n";
echo var_export(empty($a), true) . "\n";

// class introspection
class Foo {
    public $x = 1;
    protected $y = 2;
    public function bar() { return "bar"; }
    public static function baz() { return "baz"; }
}

class Bar extends Foo {}

$foo = new Foo();
echo get_class($foo) . "\n";
echo var_export(class_exists("Foo"), true) . "\n";
echo var_export(class_exists("NonExistent"), true) . "\n";
echo var_export(method_exists($foo, "bar"), true) . "\n";
echo var_export(method_exists($foo, "nonexist"), true) . "\n";
echo var_export(property_exists($foo, "x"), true) . "\n";
echo var_export(is_a($foo, "Foo"), true) . "\n";

$bar = new Bar();
echo get_parent_class($bar) . "\n";
echo var_export(is_subclass_of($bar, "Foo"), true) . "\n";

// callable check
echo var_export(is_callable("strlen"), true) . "\n";
echo var_export(is_callable("nonexistent_func"), true) . "\n";

// function_exists
echo var_export(function_exists("strlen"), true) . "\n";
echo var_export(function_exists("nope"), true) . "\n";

// define/defined/constant
define("MY_CONST", 42);
echo MY_CONST . "\n";
echo var_export(defined("MY_CONST"), true) . "\n";
echo var_export(defined("NOPE"), true) . "\n";
echo constant("MY_CONST") . "\n";

// version_compare
echo var_export(version_compare("1.0.0", "1.0.1", "<"), true) . "\n";
echo var_export(version_compare("2.0.0", "1.9.9", ">"), true) . "\n";
echo var_export(version_compare("1.0.0", "1.0.0", "=="), true) . "\n";
echo version_compare("1.0.0", "2.0.0") . "\n";

// count on various types
echo count([1, 2, 3]) . "\n";
echo count(["a" => 1, "b" => 2]) . "\n";
echo strlen("hello") . "\n";

echo "done\n";
