<?php
$fa = new SplFixedArray(5);
for ($i = 0; $i < 5; $i++) $fa[$i] = $i * 10;

foreach ($fa as $k => $v) echo "$k=$v ";
echo "\n";

$fa = SplFixedArray::fromArray([1, 2, 3, 4, 5]);
foreach ($fa as $k => $v) echo "$k=$v ";
echo "\n";

$fa = SplFixedArray::fromArray([10 => "x", 20 => "y", 30 => "z"]);
echo $fa->getSize(), "\n";
print_r($fa->toArray());

$fa = SplFixedArray::fromArray([10 => "x", 20 => "y", 30 => "z"], false);
echo $fa->getSize(), "\n";
print_r($fa->toArray());

try {
    $fa = SplFixedArray::fromArray(["a" => 1, "b" => 2]);
    echo "no\n";
} catch (\InvalidArgumentException $e) {
    echo "iae\n";
}

$fa = SplFixedArray::fromArray(["a" => 1, "b" => 2], false);
echo $fa->getSize(), "\n";
print_r($fa->toArray());

$fa = new SplFixedArray(3);
$fa[0] = "a";
$fa[1] = "b";
$fa[2] = "c";
$copy = clone $fa;
$copy[0] = "Z";
echo $fa[0], " ", $copy[0], "\n";

$fa = new SplFixedArray(100);
for ($i = 0; $i < 100; $i++) $fa[$i] = $i;
echo $fa[99], "\n";
echo count($fa), "\n";

$sum = 0;
foreach ($fa as $v) $sum += $v;
echo $sum, "\n";

$fa = new SplFixedArray(5);
$fa[0] = ["nested", "array"];
$fa[1] = (object)["k" => "v"];
$fa[2] = null;
$fa[3] = true;
$fa[4] = 3.14;

echo gettype($fa[0]), "\n";
echo gettype($fa[1]), "\n";
echo gettype($fa[2]), "\n";
echo gettype($fa[3]), "\n";
echo gettype($fa[4]), "\n";

print_r($fa->toArray());

$fa = new SplFixedArray(0);
echo $fa->getSize(), "\n";
echo count($fa), "\n";
foreach ($fa as $v) echo "no\n";

print_r($fa->toArray());

$fa = new SplFixedArray(3);
echo $fa[0] === null ? "y" : "n", "\n";
echo $fa[1] === null ? "y" : "n", "\n";
echo $fa[2] === null ? "y" : "n", "\n";

$fa[0] = 10;
$fa->setSize(5);
echo $fa->getSize(), "\n";
echo $fa[0], "\n";
echo var_export($fa[4], true), "\n";

$fa = new SplFixedArray(5);
$fa[0] = "first";
$fa[4] = "last";
$arr = $fa->toArray();
echo $arr[0], " ", var_export($arr[1], true), " ", $arr[4], "\n";

$fa = SplFixedArray::fromArray([100, 200, 300]);
$fa[1] = "B";
foreach ($fa as $k => $v) echo "$k:$v ";
echo "\n";

$fa = new SplFixedArray(3);
$fa[0] = 1;
$fa[1] = 2;
$fa[2] = 3;
echo $fa->getSize(), "\n";

$fa->setSize(5);
echo $fa->getSize(), "\n";
echo $fa[0], " ", $fa[2], " ", var_export($fa[4], true), "\n";

$fa->setSize(2);
echo $fa->getSize(), "\n";
echo $fa[0], " ", $fa[1], "\n";

$fa = SplFixedArray::fromArray(range(1, 50));
echo $fa->getSize(), "\n";
echo array_sum($fa->toArray()), "\n";

$fa = SplFixedArray::fromArray([5 => "five", 10 => "ten"]);
echo $fa->getSize(), "\n";
echo $fa[5], " ", $fa[10], "\n";
echo var_export($fa[0], true), "\n";

$fa = new SplFixedArray(4);
echo $fa instanceof Countable ? "y" : "n", "\n";
echo $fa instanceof ArrayAccess ? "y" : "n", "\n";
echo $fa instanceof Iterator ? "y" : "n", "\n";

$fa = SplFixedArray::fromArray([1.5, 2.5, 3.5]);
$result = [];
foreach ($fa as $v) $result[] = $v * 2;
print_r($result);

$fa = new SplFixedArray(10);
for ($i = 0; $i < 10; $i++) $fa[$i] = $i * $i;
$arr = $fa->toArray();
echo array_sum($arr), "\n";

class Wrap {
    public int $val;
    public function __construct(int $v) { $this->val = $v; }
}

$fa = new SplFixedArray(3);
$fa[0] = new Wrap(1);
$fa[1] = new Wrap(2);
$fa[2] = new Wrap(3);

$names = [];
foreach ($fa as $w) $names[] = $w->val;
print_r($names);

$copy = clone $fa;
$copy[0]->val = 999;
echo $fa[0]->val, "\n";
