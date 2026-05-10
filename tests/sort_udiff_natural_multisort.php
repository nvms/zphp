<?php
$a = [1, 2, 3, 4, 5];
$b = [2, 4];
print_r(array_udiff($a, $b, fn($x, $y) => $x - $y));
print_r(array_udiff([1, 2, 3], [4, 5], fn($x, $y) => $x - $y));

print_r(array_udiff_assoc(
    ["a" => 1, "b" => 2, "c" => 3],
    ["a" => 1, "b" => 9, "c" => 3],
    fn($x, $y) => $x - $y,
));

print_r(array_uintersect([1, 2, 3, 4], [2, 4, 5], fn($x, $y) => $x - $y));

class Item {
    public function __construct(public string $tag, public int $val) {}
}

$a = [new Item("x", 1), new Item("y", 2), new Item("z", 3)];
$b = [new Item("y", 2)];
$diff = array_udiff($a, $b, fn($x, $y) => strcmp($x->tag, $y->tag));
foreach ($diff as $i) echo $i->tag, " ";
echo "\n";

$pairs = [
    ["n" => 1, "id" => "a"],
    ["n" => 2, "id" => "b"],
    ["n" => 1, "id" => "c"],
    ["n" => 3, "id" => "d"],
    ["n" => 2, "id" => "e"],
    ["n" => 1, "id" => "f"],
];
usort($pairs, fn($x, $y) => $x["n"] <=> $y["n"]);
foreach ($pairs as $p) echo $p["id"], " ";
echo "\n";

$pairs2 = [
    ["k" => "a", "v" => 5],
    ["k" => "b", "v" => 3],
    ["k" => "c", "v" => 5],
    ["k" => "d", "v" => 1],
    ["k" => "e", "v" => 3],
];
usort($pairs2, fn($x, $y) => $x["v"] <=> $y["v"]);
foreach ($pairs2 as $p) echo $p["k"], "(", $p["v"], ") ";
echo "\n";

$a = ["IMG10", "img2", "Img1", "img12", "IMG3"];
sort($a, SORT_NATURAL | SORT_FLAG_CASE);
print_r($a);

$a = ["IMG10", "img2", "Img1"];
sort($a, SORT_NATURAL);
print_r($a);

$a = ["10", "2", "1", "20"];
sort($a, SORT_STRING);
print_r($a);

$a = ["10", "2", "1", "20"];
sort($a, SORT_NUMERIC);
print_r($a);

$a = ["banana", "apple", "Cherry", "date"];
sort($a, SORT_STRING | SORT_FLAG_CASE);
print_r($a);

$a = ["b" => 2, "c" => 3, "a" => 1];
ksort($a);
print_r($a);

$a = ["c" => "z", "a" => "y", "b" => "x"];
asort($a);
print_r($a);

$a = ["b" => 2, "c" => 1, "a" => 3];
arsort($a);
print_r($a);

$a = ["c" => 3, "a" => 1, "b" => 2];
krsort($a);
print_r($a);

$a = ["x_3" => "c", "y_1" => "a", "z_2" => "b"];
uksort($a, fn($x, $y) => substr($x, 2) <=> substr($y, 2));
print_r($a);

$rows = [
    ["name" => "alice", "age" => 30],
    ["name" => "bob", "age" => 25],
    ["name" => "carol", "age" => 30],
];
$ages = array_column($rows, "age");
$names = array_column($rows, "name");
array_multisort($ages, SORT_ASC, $names, SORT_ASC, $rows);
foreach ($rows as $r) echo $r["name"], "=", $r["age"], " ";
echo "\n";

$a = [3, 1, 4];
$b = ["x", "y", "z"];
array_multisort($a, $b);
print_r($a);
print_r($b);

$a = [3, 1, 4];
$b = ["x", "y", "z"];
array_multisort($a, SORT_DESC, $b);
print_r($a);
print_r($b);

$nums = ["1.5", "2.5", "0.5", "10.0"];
sort($nums, SORT_NUMERIC);
print_r($nums);

$mixed = [10, "2", 3, "20", 1];
sort($mixed, SORT_NUMERIC);
print_r($mixed);

$cs = ["b", "B", "a", "A", "c", "C"];
sort($cs, SORT_STRING);
print_r($cs);

sort($cs, SORT_STRING | SORT_FLAG_CASE);
print_r($cs);

$arr = [3, 2, 1];
$result = usort($arr, fn($x, $y) => 0);
var_dump($result);
print_r($arr);

$obj = [
    (object)["id" => 3],
    (object)["id" => 1],
    (object)["id" => 2],
];
usort($obj, fn($a, $b) => $a->id - $b->id);
foreach ($obj as $o) echo $o->id, " ";
echo "\n";

usort($obj, fn($a, $b) => $b->id - $a->id);
foreach ($obj as $o) echo $o->id, " ";
echo "\n";

$mix = [3, 1.5, 2, 2.5, 1];
usort($mix, fn($a, $b) => $a <=> $b);
print_r($mix);

$people = [
    ["name" => "alice", "age" => 30],
    ["name" => "bob", "age" => 25],
];
usort($people, fn($a, $b) => $a["age"] <=> $b["age"]);
foreach ($people as $p) echo $p["name"], " ";
echo "\n";
