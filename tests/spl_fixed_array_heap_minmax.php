<?php
$fa = new SplFixedArray(5);
echo $fa->getSize(), "\n";
echo count($fa), "\n";

$fa[0] = "a";
$fa[1] = "b";
$fa[4] = "e";
echo $fa[0], "\n";
echo $fa[1], "\n";
echo var_export($fa[2], true), "\n";
echo $fa[4], "\n";

echo isset($fa[0]) ? "y" : "n", "\n";
echo isset($fa[2]) ? "y" : "n", "\n";
echo isset($fa[10]) ? "y" : "n", "\n";

print_r($fa->toArray());

$fa->setSize(3);
echo $fa->getSize(), "\n";
print_r($fa->toArray());

$fa->setSize(6);
echo $fa->getSize(), "\n";
print_r($fa->toArray());

$fa = new SplFixedArray(3);
$fa[0] = 10;
$fa[1] = 20;
$fa[2] = 30;
foreach ($fa as $k => $v) echo $k, "=>", $v, "\n";

try {
    $x = $fa[10];
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "rt\n";
}

try {
    $fa[-1] = "x";
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "rt\n";
}

try {
    $x = $fa[-1];
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "rt\n";
}

$fa = SplFixedArray::fromArray([1, 2, 3, 4, 5]);
echo $fa->getSize(), "\n";
print_r($fa->toArray());

$fa = SplFixedArray::fromArray(["a", "b", "c"]);
echo $fa[0], $fa[1], $fa[2], "\n";

$fa = SplFixedArray::fromArray([10 => "x", 20 => "y", 30 => "z"]);
echo $fa->getSize(), "\n";
print_r($fa->toArray());

$fa = SplFixedArray::fromArray([10 => "x", 20 => "y", 30 => "z"], false);
echo $fa->getSize(), "\n";
print_r($fa->toArray());

$fa = new SplFixedArray(0);
echo $fa->getSize(), "\n";
foreach ($fa as $v) echo "no\n";

class MinHeap extends SplMinHeap {}
$h = new MinHeap;
$h->insert(5);
$h->insert(1);
$h->insert(3);
$h->insert(10);
$h->insert(2);
echo $h->count(), "\n";
echo $h->top(), "\n";

$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

class MaxHeap extends SplMaxHeap {}
$h = new MaxHeap;
$h->insert(5);
$h->insert(1);
$h->insert(3);
$h->insert(10);
$h->insert(2);
echo $h->top(), "\n";

$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

class CustomHeap extends SplHeap {
    protected function compare(mixed $a, mixed $b): int {
        return strcmp($a["name"], $b["name"]);
    }
}

$h = new CustomHeap;
$h->insert(["name" => "charlie"]);
$h->insert(["name" => "alice"]);
$h->insert(["name" => "bob"]);
echo $h->count(), "\n";
$out = [];
while (!$h->isEmpty()) $out[] = $h->extract()["name"];
print_r($out);

class RevHeap extends SplHeap {
    protected function compare(mixed $a, mixed $b): int {
        return $b - $a;
    }
}

$h = new RevHeap;
$h->insert(5);
$h->insert(1);
$h->insert(3);
echo $h->top(), "\n";
$out = [];
while (!$h->isEmpty()) $out[] = $h->extract();
print_r($out);

$h = new MinHeap;
echo $h->isEmpty() ? "y" : "n", "\n";
echo $h->count(), "\n";
try {
    $h->top();
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "re\n";
}

$h = new MinHeap;
for ($i = 100; $i > 0; $i--) $h->insert($i);
echo $h->count(), " ", $h->top(), "\n";

$h = new MinHeap;
$h->insert(1);
$h->insert(2);
$h->insert(3);
foreach ($h as $k => $v) echo $k, "=", $v, "\n";

$fa = new SplFixedArray(4);
$fa[0] = ["nested", "array"];
$fa[1] = (object)["x" => 1];
$fa[2] = null;
$fa[3] = true;
echo gettype($fa[0]), " ", gettype($fa[1]), " ", gettype($fa[2]), " ", gettype($fa[3]), "\n";

$fa = SplFixedArray::fromArray([1, 2, 3]);
$fa[1] = 99;
print_r($fa->toArray());

$fa = new SplFixedArray(3);
echo $fa[0] === null ? "y" : "n", "\n";
echo $fa[1] === null ? "y" : "n", "\n";

$h = new MaxHeap;
$h->insert(1.5);
$h->insert(2.5);
$h->insert(0.5);
echo $h->extract(), " ", $h->extract(), " ", $h->extract(), "\n";

$h = new MinHeap;
$h->insert("c");
$h->insert("a");
$h->insert("b");
echo $h->extract(), " ", $h->extract(), " ", $h->extract(), "\n";
