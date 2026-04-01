<?php
// covers: current, next, prev, reset, end, key, array internal pointer

// --- basic sequential array ---

$arr = [10, 20, 30, 40, 50];

echo "=== Sequential array ===\n";
echo "current: " . current($arr) . "\n";
echo "key: " . key($arr) . "\n";

next($arr);
echo "after next - current: " . current($arr) . "\n";
echo "after next - key: " . key($arr) . "\n";

next($arr);
next($arr);
echo "after 3 nexts - current: " . current($arr) . "\n";
echo "after 3 nexts - key: " . key($arr) . "\n";

prev($arr);
echo "after prev - current: " . current($arr) . "\n";
echo "after prev - key: " . key($arr) . "\n";

end($arr);
echo "after end - current: " . current($arr) . "\n";
echo "after end - key: " . key($arr) . "\n";

reset($arr);
echo "after reset - current: " . current($arr) . "\n";
echo "after reset - key: " . key($arr) . "\n";

// --- associative array ---

$assoc = ['a' => 'apple', 'b' => 'banana', 'c' => 'cherry', 'd' => 'date'];

echo "\n=== Associative array ===\n";
echo "current: " . current($assoc) . "\n";
echo "key: " . key($assoc) . "\n";

next($assoc);
echo "after next - current: " . current($assoc) . "\n";
echo "after next - key: " . key($assoc) . "\n";

end($assoc);
echo "after end - current: " . current($assoc) . "\n";
echo "after end - key: " . key($assoc) . "\n";

prev($assoc);
echo "after prev - current: " . current($assoc) . "\n";
echo "after prev - key: " . key($assoc) . "\n";

// --- pointer past end ---

echo "\n=== Pointer past end ===\n";
$small = [100, 200];
end($small);
$result = next($small);
echo "next past end: ";
var_dump($result);
echo "current past end: ";
var_dump(current($small));
echo "key past end: ";
var_dump(key($small));

reset($small);
echo "after reset from past-end: " . current($small) . "\n";

// --- prev before start ---

echo "\n=== Pointer before start ===\n";
$small2 = [100, 200];
$result = prev($small2);
echo "prev before start: ";
var_dump($result);
echo "current before start: ";
var_dump(current($small2));
echo "key before start: ";
var_dump(key($small2));

// --- empty array ---

echo "\n=== Empty array ===\n";
$empty = [];
echo "current on empty: ";
var_dump(current($empty));
echo "key on empty: ";
var_dump(key($empty));
echo "next on empty: ";
var_dump(next($empty));
echo "prev on empty: ";
var_dump(prev($empty));
echo "reset on empty: ";
var_dump(reset($empty));
echo "end on empty: ";
var_dump(end($empty));

// --- single element ---

echo "\n=== Single element ===\n";
$single = ['only' => 42];
echo "current: " . current($single) . "\n";
echo "key: " . key($single) . "\n";
echo "next: ";
var_dump(next($single));
echo "after next - current: ";
var_dump(current($single));
reset($single);
echo "after reset - current: " . current($single) . "\n";
echo "prev: ";
var_dump(prev($single));
echo "after prev - current: ";
var_dump(current($single));

// --- independent pointers on separate arrays ---

echo "\n=== Independent pointers ===\n";
$arr1 = ['x', 'y', 'z'];
$arr2 = [1, 2, 3, 4];

next($arr1);
next($arr2);
next($arr2);

echo "arr1 current: " . current($arr1) . "\n";
echo "arr1 key: " . key($arr1) . "\n";
echo "arr2 current: " . current($arr2) . "\n";
echo "arr2 key: " . key($arr2) . "\n";

reset($arr1);
echo "arr1 after reset: " . current($arr1) . "\n";
echo "arr2 unchanged: " . current($arr2) . "\n";

// --- walking with next ---

echo "\n=== Walking with next ===\n";
$walk = ['first', 'second', 'third'];
$val = current($walk);
while ($val !== false) {
    echo "walk: $val\n";
    $val = next($walk);
}

// --- pointer after unset ---

echo "\n=== Pointer after unset ===\n";
$mod = [10, 20, 30, 40, 50];
next($mod);
next($mod);
echo "before unset - current: " . current($mod) . "\n";
echo "before unset - key: " . key($mod) . "\n";
unset($mod[2]);
echo "after unset current element - current: ";
var_dump(current($mod));
echo "after unset current element - key: ";
var_dump(key($mod));

// --- pointer after adding elements ---

echo "\n=== Pointer after adding elements ===\n";
$grow = ['a', 'b'];
next($grow);
echo "before add - current: " . current($grow) . "\n";
$grow[] = 'c';
echo "after add - current: " . current($grow) . "\n";
echo "after add - key: " . key($grow) . "\n";

// --- reset return value ---

echo "\n=== Reset and end return values ===\n";
$ret = [100, 200, 300];
$r = reset($ret);
echo "reset returns: " . $r . "\n";
$e = end($ret);
echo "end returns: " . $e . "\n";

echo "\nDone.\n";
