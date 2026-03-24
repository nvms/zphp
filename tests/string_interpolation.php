<?php

$name = "World";
$arr = ["key" => "value", "num" => 42];
$nested = ["a" => ["b" => "deep"]];

class Obj {
    public $prop = "test";
    public $items = ["x", "y", "z"];
    public function getVal() { return "method_result"; }
}
$obj = new Obj();

// simple variable
echo "Hello $name\n";

// simple array (no quotes on key in interpolation)
echo "Got: $arr[key]\n";

// curly: simple variable
echo "Curly: {$name}\n";

// curly: property access
echo "Prop: {$obj->prop}\n";

// curly: array with quoted key
echo "Arr: {$arr['key']}\n";

// curly: chained array access
echo "Deep: {$nested['a']['b']}\n";

// curly: method call
echo "Method: {$obj->getVal()}\n";

// curly: property that is an array, then index
echo "PropArr: {$obj->items[0]}\n";

// numeric array index
$list = ["a", "b", "c"];
echo "List: $list[0] $list[2]\n";

// multiple interpolations in one string
echo "Multi: $name and {$arr['key']}\n";

// interpolation with surrounding text
echo "before_{$name}_after\n";

// escaped dollar (should not interpolate)
echo "Escaped: \$name\n";

// variable at end of string
echo "End: $name";
echo "\n";

// empty/null interpolation
$empty = "";
$null_var = null;
echo "Empty: '{$empty}'\n";
echo "Null: '{$null_var}'\n";

echo "done\n";
