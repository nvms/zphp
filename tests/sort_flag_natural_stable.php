<?php
$a = ["B" => 1, "a" => 2, "C" => 3];
ksort($a, SORT_STRING | SORT_FLAG_CASE);
print_r($a);

$a = ["B" => 1, "a" => 2, "C" => 3];
ksort($a, SORT_STRING);
print_r($a);

$a = ["b" => 2, "a" => 1, "c" => 3];
ksort($a);
print_r($a);

$a = ["IMG10" => 1, "IMG2" => 2, "IMG1" => 3];
ksort($a, SORT_NATURAL);
print_r($a);

$a = ["IMG10" => 1, "img2" => 2, "Img1" => 3];
ksort($a, SORT_NATURAL | SORT_FLAG_CASE);
print_r($a);

$a = ["c" => "z", "a" => "y", "b" => "x"];
asort($a);
print_r($a);

$a = ["c" => "z", "a" => "y", "b" => "x"];
asort($a, SORT_STRING);
print_r($a);

$a = ["c" => "10", "a" => "2", "b" => "1"];
asort($a, SORT_NUMERIC);
print_r($a);

$a = ["c" => "10", "a" => "2", "b" => "1"];
asort($a, SORT_STRING);
print_r($a);

$a = ["c" => "10", "a" => "2", "b" => "1"];
asort($a, SORT_NATURAL);
print_r($a);

$a = ["c" => "Z", "a" => "z", "b" => "Y"];
asort($a, SORT_STRING | SORT_FLAG_CASE);
print_r($a);

$a = [3, 1, 2];
uasort($a, fn($x, $y) => $x - $y);
print_r($a);

$a = [3, 1, 2];
usort($a, fn($x, $y) => $x - $y);
print_r($a);

$a = ["c" => 3, "a" => 1, "b" => 2];
uksort($a, fn($x, $y) => strcmp($x, $y));
print_r($a);

$a = ["X_3" => "c", "Y_1" => "a", "Z_2" => "b"];
uksort($a, fn($x, $y) => substr($x, 2) <=> substr($y, 2));
print_r($a);

$a = ["B" => 1, "a" => 2, "C" => 3];
uksort($a, "strcasecmp");
print_r($a);

$arr = [
    ["n" => 1, "id" => "a"],
    ["n" => 2, "id" => "b"],
    ["n" => 1, "id" => "c"],
    ["n" => 3, "id" => "d"],
    ["n" => 2, "id" => "e"],
    ["n" => 1, "id" => "f"],
];
usort($arr, fn($x, $y) => $x["n"] <=> $y["n"]);
foreach ($arr as $r) echo $r["id"], " ";
echo "\n";

$arr2 = [
    ["k" => "a", "v" => 5],
    ["k" => "b", "v" => 3],
    ["k" => "c", "v" => 5],
    ["k" => "d", "v" => 1],
];
usort($arr2, fn($x, $y) => $x["v"] <=> $y["v"]);
foreach ($arr2 as $p) echo $p["k"], "(", $p["v"], ") ";
echo "\n";

$equals = [
    ["k" => "first"],
    ["k" => "second"],
    ["k" => "third"],
];
usort($equals, fn($x, $y) => 0);
foreach ($equals as $e) echo $e["k"], " ";
echo "\n";

$nums = [10, 5, 20, 1];
sort($nums, SORT_NUMERIC);
print_r($nums);

$strs = ["banana", "apple", "cherry"];
sort($strs);
print_r($strs);

rsort($nums);
print_r($nums);
$a = ["a" => 1, "b" => 3, "c" => 2]; arsort($a);
print_r($a);
$a = ["a" => 1, "b" => 2, "c" => 3]; krsort($a);
print_r($a);

$mixed_keys = [10 => "a", "5" => "b", 20 => "c"];
ksort($mixed_keys);
print_r($mixed_keys);

$natural = ["item10", "item2", "item1", "item20"];
sort($natural, SORT_NATURAL);
print_r($natural);

natsort($natural);
print_r($natural);

$ci = ["IMG10", "img2", "Img1"];
natcasesort($ci);
print_r($ci);

$by_len = ["hello", "hi", "hey"];
usort($by_len, fn($a, $b) => strlen($a) - strlen($b));
print_r($by_len);

class P {
    public function __construct(public int $age, public string $name) {}
}
$people = [new P(30, "alice"), new P(25, "bob"), new P(40, "carol")];
usort($people, fn($a, $b) => $a->age - $b->age);
foreach ($people as $p) echo $p->name, ":", $p->age, " ";
echo "\n";

class By implements Stringable {
    public function __construct(public int $n) {}
    public function __toString(): string { return "By($this->n)"; }
}
$objs = [new By(3), new By(1), new By(2)];
usort($objs, fn($a, $b) => $a->n <=> $b->n);
foreach ($objs as $o) echo (string)$o, " ";
echo "\n";

$mixed = [3, "a", 1, "b", 2];
usort($mixed, fn($a, $b) => is_string($a) <=> is_string($b) ?: $a <=> $b);
print_r($mixed);

$priorities = [
    ["name" => "alice", "level" => 3, "added" => 1],
    ["name" => "bob", "level" => 1, "added" => 2],
    ["name" => "carol", "level" => 3, "added" => 3],
    ["name" => "dave", "level" => 2, "added" => 4],
    ["name" => "eve", "level" => 1, "added" => 5],
];
usort($priorities, fn($a, $b) => $a["level"] <=> $b["level"] ?: $a["added"] <=> $b["added"]);
foreach ($priorities as $p) echo $p["name"], " ";
echo "\n";
