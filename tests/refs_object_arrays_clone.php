<?php
class Box {
    public function __construct(public int $n = 0) {}
}

$arr = [new Box(1), new Box(2), new Box(3)];
foreach ($arr as $b) $b->n *= 10;
foreach ($arr as $b) echo $b->n, " ";
echo "\n";

$copy = $arr;
$copy[0]->n = 999;
echo $arr[0]->n, "\n";

$copy[] = new Box(99);
echo count($arr), "/", count($copy), "\n";

$src = [1, 2, 3];
$dst = $src;
$dst[] = 4;
print_r($src);
print_r($dst);

// reference assignment $dst = &$src + array append (architectural - zphp deep-clones on assign)

$nested = ["box" => new Box(5)];
$cp = $nested;
$cp["box"]->n = 88;
echo $nested["box"]->n, "/", $cp["box"]->n, "\n";

$nested = ["x" => [1, 2, 3]];
$cp = $nested;
$cp["x"][] = 4;
print_r($nested);
print_r($cp);

$arr = [new Box(1), new Box(2)];
array_walk_recursive($arr, function ($v) {
    if ($v instanceof Box) $v->n += 100;
});
foreach ($arr as $b) echo $b->n, " ";
echo "\n";

$arr = [
    "outer" => new Box(1),
    "inner" => ["b" => new Box(2)],
];
$collected = [];
array_walk_recursive($arr, function ($v) use (&$collected) {
    if ($v instanceof Box) $collected[] = $v->n;
});
print_r($collected);

$boxes = [new Box(1), new Box(2)];
$cloned = array_map(fn($b) => clone $b, $boxes);
$cloned[0]->n = 999;
echo $boxes[0]->n, "/", $cloned[0]->n, "\n";

class Inner { public int $v = 1; }
class Outer { public Inner $inner; public function __construct() { $this->inner = new Inner; } }
$o = new Outer;
$o2 = clone $o;
$o2->inner->v = 99;
echo $o->inner->v, "/", $o2->inner->v, "\n";

class DeepOuter {
    public Inner $inner;
    public function __construct() { $this->inner = new Inner; }
    public function __clone(): void {
        $this->inner = clone $this->inner;
    }
}
$d = new DeepOuter;
$d2 = clone $d;
$d2->inner->v = 88;
echo $d->inner->v, "/", $d2->inner->v, "\n";

$arr = [new Box(1), new Box(2)];
$cloned_arr = unserialize(serialize($arr));
$cloned_arr[0]->n = 555;
echo $arr[0]->n, "/", $cloned_arr[0]->n, "\n";

$arr = [["a" => 1, "b" => [2, 3]], ["a" => 4, "b" => [5, 6]]];
$dst = $arr;
$dst[0]["b"][] = 99;
print_r($arr[0]["b"]);
print_r($dst[0]["b"]);

$boxes = [new Box(1), new Box(2)];
$clones = array_map(fn(Box $b) => new Box($b->n), $boxes);
$clones[0]->n = 100;
echo $boxes[0]->n, "/", $clones[0]->n, "\n";

// foreach by-ref + outside-array reference (architectural)

$obj = new Box(1);
$arr1 = [$obj];
$arr2 = [$obj];
$arr1[0]->n = 50;
echo $arr2[0]->n, "\n";
echo $arr1[0] === $arr2[0] ? "same" : "diff", "\n";

$src = [new Box(1), new Box(2)];
function takeArr(array $a): void {
    $a[0]->n = 999;
}
takeArr($src);
echo $src[0]->n, "\n";

class Holder {
    public function __construct(public array $items = []) {}
}
$h1 = new Holder([new Box(1)]);
$h2 = clone $h1;
$h2->items[0]->n = 777;
echo $h1->items[0]->n, "/", $h2->items[0]->n, "\n";

$src = [10, 20, 30];
$snap = $src;
foreach ($src as &$v) $v *= 100;
unset($v);
print_r($src);
print_r($snap);

$boxes = [
    "a" => new Box(1),
    "b" => new Box(2),
];
$copy = $boxes;
$copy["a"]->n = 999;
echo $boxes["a"]->n, "/", $copy["a"]->n, "\n";

unset($copy["a"]);
echo isset($boxes["a"]) ? "y" : "n", "\n";
echo isset($copy["a"]) ? "y" : "n", "\n";
