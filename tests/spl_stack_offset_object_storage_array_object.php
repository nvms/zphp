<?php
$s = new SplStack;
$s->push("a");
$s->push("b");
$s->push("c");
echo $s[0], " ", $s[1], " ", $s[2], "\n";
echo $s->count(), "\n";

$s[1] = "B";
echo $s[1], "\n";
echo $s->count(), "\n";

echo isset($s[0]) ? "y" : "n", "\n";
echo isset($s[10]) ? "y" : "n", "\n";

$s = new SplStack;
echo $s->isEmpty() ? "y" : "n", "\n";

$os = new SplObjectStorage;
$a = new stdClass; $a->id = 1;
$b = new stdClass; $b->id = 2;
$os[$a] = "data-a";
$os[$b] = "data-b";

echo $os[$a], "\n";
echo $os->offsetGet($a), "\n";
echo $os->offsetExists($a) ? "y" : "n", "\n";
echo $os->offsetExists(new stdClass) ? "y" : "n", "\n";

$os->offsetSet($a, "new-data");
echo $os[$a], "\n";

$os->offsetUnset($a);
echo isset($os[$a]) ? "y" : "n", "\n";
echo count($os), "\n";

$ao = new ArrayObject([
    "users" => [
        ["name" => "alice", "tags" => ["admin", "user"]],
        ["name" => "bob", "tags" => ["user"]],
    ],
    "count" => 2,
]);

$copy = $ao->getArrayCopy();
print_r($copy);

$ao["users"][0]["name"] = "ALICE";
print_r($ao->getArrayCopy());
print_r($copy);

$ao = new ArrayObject();
$ao["a"] = [1, 2, 3];
$ao["b"] = ["x" => "y"];
$copy = $ao->getArrayCopy();
$copy["a"][] = 99;
print_r($copy);
print_r($ao->getArrayCopy());

$ao = new ArrayObject([1, 2, 3]);
$ao->append(4);
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["a" => 1, "b" => 2, "c" => 3]);
unset($ao["b"]);
print_r($ao->getArrayCopy());

$ao = new ArrayObject();
$ao[] = "auto1";
$ao[] = "auto2";
$ao["named"] = "named";
print_r($ao->getArrayCopy());

$ao = new ArrayObject([3, 1, 2, 5, 4]);
$ao->ksort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["c" => 3, "a" => 1, "b" => 2]);
$ao->ksort();
print_r($ao->getArrayCopy());

$dll = new SplDoublyLinkedList;
$dll->push("a");
$dll->push("b");
$dll->push("c");
echo $dll[0], " ", $dll[1], " ", $dll[2], "\n";

$q = new SplQueue;
$q->enqueue("first");
$q->enqueue("second");
$q->enqueue("third");
echo $q[0], " ", $q[1], " ", $q[2], "\n";

$os = new SplObjectStorage;
$x = new stdClass;
$y = new stdClass;
$z = new stdClass;
$os[$x] = "x";
$os[$y] = "y";
$os[$z] = "z";

$count = 0;
foreach ($os as $obj) {
    $count++;
    echo $os[$obj], " ";
}
echo "\n", $count, "\n";

foreach ($os as $key => $obj) {
    echo $key, ":", $os[$obj], " ";
}
echo "\n";

$os = new SplObjectStorage;
echo $os->count(), "\n";
echo $os->count() === 0 ? "y" : "n", "\n";

$f1 = new stdClass;
$f2 = new stdClass;
$os->attach($f1, "f1");
$os->attach($f2, "f2");
echo $os->count(), "\n";

$ao = new ArrayObject(["c" => 3, "a" => 1, "b" => 2]);
$copy = $ao->getArrayCopy();
$ao->ksort();
print_r($copy);
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["x" => 10, "y" => 20]);
$another = clone $ao;
$another["x"] = 99;
echo $ao["x"], " ", $another["x"], "\n";

$nested = new ArrayObject([
    "level1" => new ArrayObject([
        "level2" => ["a", "b", "c"],
    ]),
]);
echo $nested["level1"]["level2"][1], "\n";
