<?php
$ao = new ArrayObject(["b" => 2, "a" => 1, "c" => 3]);
$ao->ksort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["b" => 2, "a" => 1, "c" => 3]);
$ao->asort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject([3, 1, 2]);
$ao->asort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["c" => 3, "a" => 1, "b" => 2]);
$ao->uasort(fn($a, $b) => $a - $b);
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["c" => 1, "a" => 2, "b" => 3]);
$ao->uksort(fn($a, $b) => strcmp($a, $b));
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["banana", "apple", "cherry"]);
$ao->natsort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["B", "a", "C", "b"]);
$ao->natcasesort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["k3" => 30, "k1" => 10, "k2" => 20]);
$ao->ksort();
print_r($ao->getArrayCopy());
echo $ao["k1"], " ", $ao["k2"], " ", $ao["k3"], "\n";

$ao = new ArrayObject(["item10", "item2", "item1"]);
$ao->natsort();
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";

$ao = new ArrayObject([3, 1, 2]);
$copy_before = $ao->getArrayCopy();
$ao->asort();
$copy_after = $ao->getArrayCopy();
print_r($copy_before);
print_r($copy_after);

class Numeric implements IteratorAggregate, Countable {
    public function __construct(private array $items) {}
    public function getIterator(): ArrayIterator {
        return new ArrayIterator($this->items);
    }
    public function count(): int {
        return count($this->items);
    }
}

$n = new Numeric([3, 1, 4, 1, 5]);
echo count($n), "\n";
foreach ($n as $v) echo $v, " ";
echo "\n";

$arr = iterator_to_array($n);
print_r($arr);

class TaggedItems implements IteratorAggregate {
    private array $tags = [];
    public function add(string $tag, int $val): void {
        $this->tags[$tag] = $val;
    }
    public function getIterator(): ArrayIterator {
        return new ArrayIterator($this->tags);
    }
}

$t = new TaggedItems;
$t->add("a", 10);
$t->add("b", 20);
$t->add("c", 30);
foreach ($t as $k => $v) echo "$k=$v ";
echo "\n";

$ao = new ArrayObject(["x" => 5, "y" => 1, "z" => 3]);
$ao->ksort();
$out = [];
foreach ($ao as $k => $v) $out[] = "$k=$v";
echo implode(",", $out), "\n";

$ao = new ArrayObject(["fruit" => "apple", "veg" => "carrot", "meat" => "chicken"]);
$ao->asort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["banana10", "banana2", "banana1"]);
$ao->natsort();
foreach ($ao as $k => $v) echo $k, ":", $v, " ";
echo "\n";

$ao = new ArrayObject(["c" => 3, "a" => 1, "b" => 2]);
$ao->ksort(SORT_STRING);
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["10" => "a", "2" => "b", "1" => "c"]);
$ao->ksort(SORT_NUMERIC);
print_r($ao->getArrayCopy());

class Container implements IteratorAggregate {
    public function __construct(private array $data) {}
    public function getIterator(): Iterator {
        return new ArrayIterator($this->data);
    }
}

$c = new Container([1, 2, 3, 4]);
$sum = 0;
foreach ($c as $v) $sum += $v;
echo $sum, "\n";

$c = new Container(["a", "b", "c"]);
echo count(iterator_to_array($c)), "\n";

$ao = new ArrayObject([5, 3, 8, 1]);
$ao->uasort(fn($a, $b) => $a <=> $b);
foreach ($ao as $k => $v) echo $k, ":", $v, " ";
echo "\n";

$ao = new ArrayObject(["one" => 1, "two" => 2, "three" => 3]);
$ao->uksort(fn($a, $b) => strlen($a) - strlen($b));
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";

class NumberGen implements IteratorAggregate {
    public function __construct(private int $count) {}
    public function getIterator(): Generator {
        for ($i = 0; $i < $this->count; $i++) yield $i;
    }
}

$g = new NumberGen(5);
$out = [];
foreach ($g as $v) $out[] = $v;
print_r($out);

$arr = iterator_to_array(new NumberGen(3));
print_r($arr);

$ao = new ArrayObject([
    ["name" => "alice", "age" => 30],
    ["name" => "bob", "age" => 25],
    ["name" => "carol", "age" => 35],
]);

$ao->uasort(fn($a, $b) => $a["age"] - $b["age"]);
foreach ($ao as $u) echo $u["name"], " ";
echo "\n";

$ao = new ArrayObject(["alpha", "beta", "gamma"]);
$ao->ksort();
foreach ($ao as $k => $v) echo "$k:$v ";
echo "\n";
