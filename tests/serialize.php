<?php

// --- serialize scalars ---

echo "=== serialize scalars ===\n";
echo serialize(null) . "\n";
echo serialize(true) . "\n";
echo serialize(false) . "\n";
echo serialize(0) . "\n";
echo serialize(42) . "\n";
echo serialize(-99) . "\n";
echo serialize(PHP_INT_MAX) . "\n";
echo serialize(PHP_INT_MIN) . "\n";
echo serialize(3.14) . "\n";
echo serialize(0.0) . "\n";
echo serialize(-0.0) . "\n";
echo serialize(-273.15) . "\n";
echo serialize(0.000001) . "\n";
echo serialize(1.5e2) . "\n";
echo serialize(1.0e10) . "\n";
echo serialize("") . "\n";
echo serialize("hello") . "\n";
echo serialize("hello world") . "\n";
echo serialize("line1\nline2") . "\n";
echo serialize("tab\there") . "\n";
echo serialize("quote\"inside") . "\n";
echo serialize("back\\slash") . "\n";
echo serialize("special: <>&") . "\n";

// --- serialize arrays ---

echo "=== serialize arrays ===\n";
echo serialize([]) . "\n";
echo serialize([1, 2, 3]) . "\n";
echo serialize(["a" => 1, "b" => 2]) . "\n";
echo serialize([0 => "zero", 1 => "one", 2 => "two"]) . "\n";
echo serialize(["x" => 10, 0 => "mixed", "y" => 20]) . "\n";
echo serialize([10 => "a", 20 => "b"]) . "\n";

// nested arrays
echo serialize(["a" => [1, 2, 3], "b" => ["nested" => true]]) . "\n";
echo serialize([[1, 2], [3, 4]]) . "\n";
echo serialize(["deep" => ["level2" => ["level3" => "value"]]]) . "\n";

// mixed value types in array
echo serialize([null, true, false, 42, 3.14, "str"]) . "\n";

// --- unserialize scalars ---

echo "=== unserialize scalars ===\n";
var_dump(unserialize("N;"));
var_dump(unserialize("b:1;"));
var_dump(unserialize("b:0;"));
var_dump(unserialize("i:0;"));
var_dump(unserialize("i:42;"));
var_dump(unserialize("i:-99;"));
var_dump(unserialize("d:3.14;"));
var_dump(unserialize("d:0;"));
var_dump(unserialize("s:0:\"\";"));
var_dump(unserialize("s:5:\"hello\";"));
var_dump(unserialize("s:11:\"hello world\";"));

// --- round-trip scalars ---

echo "=== round-trip scalars ===\n";
$values = [null, true, false, 0, 42, -99, 3.14, "", "hello", "quote\"test", "back\\slash"];
foreach ($values as $v) {
    $s = serialize($v);
    $u = unserialize($s);
    if ($v === null) {
        echo "null: " . ($u === null ? "ok" : "FAIL") . "\n";
    } elseif (is_bool($v)) {
        echo "bool(" . ($v ? "true" : "false") . "): " . ($u === $v ? "ok" : "FAIL") . "\n";
    } elseif (is_int($v)) {
        echo "int($v): " . ($u === $v ? "ok" : "FAIL") . "\n";
    } elseif (is_float($v)) {
        echo "float($v): " . ($u === $v ? "ok" : "FAIL") . "\n";
    } elseif (is_string($v)) {
        echo "string(\"$v\"): " . ($u === $v ? "ok" : "FAIL") . "\n";
    }
}

// --- round-trip arrays ---

echo "=== round-trip arrays ===\n";

$arr1 = ["name" => "John", "age" => 30, "active" => true];
$back1 = unserialize(serialize($arr1));
echo $back1["name"] . "\n";
echo $back1["age"] . "\n";
echo $back1["active"] ? "true" : "false";
echo "\n";

$arr2 = ["a" => [1, 2], "b" => "test"];
$back2 = unserialize(serialize($arr2));
echo $back2["a"][0] . "\n";
echo $back2["a"][1] . "\n";
echo $back2["b"] . "\n";

$arr3 = [[1, 2], [3, 4], [5]];
$back3 = unserialize(serialize($arr3));
echo $back3[0][0] . "\n";
echo $back3[1][1] . "\n";
echo $back3[2][0] . "\n";

$arr4 = [];
$back4 = unserialize(serialize($arr4));
echo "empty array count: " . count($back4) . "\n";

// deep nesting
$deep = ["l1" => ["l2" => ["l3" => ["l4" => "deep"]]]];
$backDeep = unserialize(serialize($deep));
echo $backDeep["l1"]["l2"]["l3"]["l4"] . "\n";

// mixed keys
$mixed = ["a" => 1, 0 => "zero", "b" => 2, 1 => "one"];
$backMixed = unserialize(serialize($mixed));
echo $backMixed["a"] . "\n";
echo $backMixed[0] . "\n";
echo $backMixed["b"] . "\n";
echo $backMixed[1] . "\n";

// --- malformed input ---

echo "=== malformed input ===\n";
var_dump(@unserialize(""));
var_dump(@unserialize("garbage"));
var_dump(@unserialize("i:;"));
var_dump(@unserialize("s:5:\"hi\";"));
var_dump(@unserialize("{bad}"));
var_dump(@unserialize("x:1;"));

// --- strings with special characters ---

echo "=== special strings ===\n";
$specials = [
    "with\nnewline",
    "with\ttab",
    "with \"quotes\"",
    "with 'single'",
    "back\\slash\\path",
    "null\x00byte",
    "unicode cafe",
];
foreach ($specials as $s) {
    $round = unserialize(serialize($s));
    echo ($round === $s ? "ok" : "FAIL") . "\n";
}

// --- large integers ---

echo "=== large integers ===\n";
$large = 999999999;
$backLarge = unserialize(serialize($large));
echo ($backLarge === $large ? "ok" : "FAIL") . "\n";

$negLarge = -999999999;
$backNegLarge = unserialize(serialize($negLarge));
echo ($backNegLarge === $negLarge ? "ok" : "FAIL") . "\n";

// --- float edge cases ---

echo "=== float edge cases ===\n";
$floats = [0.0, -0.0, 1.5, -1.5, 0.000001, 999999.999999];
foreach ($floats as $f) {
    $back = unserialize(serialize($f));
    echo (is_float($back) && $back == $f ? "ok" : "FAIL") . "\n";
}

// --- array with all value types ---

echo "=== mixed type array ===\n";
$all = [
    "null" => null,
    "true" => true,
    "false" => false,
    "int" => 42,
    "float" => 3.14,
    "string" => "hello",
    "array" => [1, 2, 3],
];
$backAll = unserialize(serialize($all));
echo ($backAll["null"] === null ? "ok" : "FAIL") . "\n";
echo ($backAll["true"] === true ? "ok" : "FAIL") . "\n";
echo ($backAll["false"] === false ? "ok" : "FAIL") . "\n";
echo ($backAll["int"] === 42 ? "ok" : "FAIL") . "\n";
echo ($backAll["float"] === 3.14 ? "ok" : "FAIL") . "\n";
echo ($backAll["string"] === "hello" ? "ok" : "FAIL") . "\n";
echo ($backAll["array"][0] === 1 ? "ok" : "FAIL") . "\n";
echo ($backAll["array"][2] === 3 ? "ok" : "FAIL") . "\n";

echo "=== done ===\n";
