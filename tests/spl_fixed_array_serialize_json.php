<?php
$fa = SplFixedArray::fromArray([10, 20, 30]);
echo serialize($fa), "\n";

$un = unserialize(serialize($fa));
echo get_class($un), "\n";
echo $un->getSize(), "\n";
foreach ($un as $v) echo $v, " ";
echo "\n";

echo json_encode($fa), "\n";

$fa2 = new SplFixedArray(5);
for ($i = 0; $i < 5; $i++) $fa2[$i] = $i * 100;
$fa2[2] = null;
echo serialize($fa2), "\n";
echo json_encode($fa2), "\n";

$un2 = unserialize(serialize($fa2));
echo $un2->getSize(), "\n";
foreach ($un2 as $v) echo ($v ?? "null"), " ";
echo "\n";

$mixed = SplFixedArray::fromArray([1, "two", 3.14, true, null, [1, 2]]);
echo json_encode($mixed), "\n";

$big = new SplFixedArray(10);
$big[0] = "a";
$big[5] = "f";
$big[9] = "j";
$un = unserialize(serialize($big));
echo $un->getSize(), "\n";
echo $un[0] ?? "n", " ", $un[5] ?? "n", " ", $un[9] ?? "n", "\n";
echo $un[1] === null ? "y" : "n", "\n";
