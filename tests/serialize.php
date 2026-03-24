<?php

// serialize scalars
echo serialize(null) . "\n";
echo serialize(true) . "\n";
echo serialize(false) . "\n";
echo serialize(42) . "\n";
echo serialize(3.14) . "\n";
echo serialize("hello") . "\n";

// serialize array
echo serialize([1, 2, 3]) . "\n";
echo serialize(["a" => 1, "b" => 2]) . "\n";

// unserialize
var_dump(unserialize("N;"));
var_dump(unserialize("b:1;"));
var_dump(unserialize("i:42;"));
var_dump(unserialize("s:5:\"hello\";"));

// round-trip array
$arr = ["name" => "John", "age" => 30, "active" => true];
$s = serialize($arr);
$back = unserialize($s);
echo $back["name"] . "\n";
echo $back["age"] . "\n";
echo $back["active"] ? "true" : "false";
echo "\n";

// nested
$nested = ["a" => [1, 2], "b" => "test"];
$s2 = serialize($nested);
$back2 = unserialize($s2);
echo $back2["a"][0] . "\n";
echo $back2["b"] . "\n";
