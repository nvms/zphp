<?php
$ao = new ArrayObject([1, 2, 3]);
echo $ao->getIteratorClass(), "\n";

$ao->setIteratorClass("ArrayIterator");
echo $ao->getIteratorClass(), "\n";

class MyIterator extends ArrayIterator {
    public function current(): mixed {
        return strtoupper((string)parent::current());
    }
}

$ao = new ArrayObject(["a", "b", "c"]);
$ao->setIteratorClass("MyIterator");
echo $ao->getIteratorClass(), "\n";

foreach ($ao as $v) echo $v, " ";
echo "\n";

$it = $ao->getIterator();
echo get_class($it), "\n";

$ao = new ArrayObject(["a", "b", "c"], 0, "MyIterator");
echo $ao->getIteratorClass(), "\n";
foreach ($ao as $v) echo $v, " ";
echo "\n";

$outer = new ArrayObject([
    "first" => new ArrayObject([1, 2, 3]),
    "second" => new ArrayObject([4, 5, 6]),
]);

foreach ($outer as $name => $inner) {
    echo $name, ":";
    foreach ($inner as $v) echo $v;
    echo " ";
}
echo "\n";

echo count($outer["first"]), "\n";
echo count($outer["second"]), "\n";

$copy = clone $outer;
$copy["first"][0] = 99;
echo $outer["first"][0], " ", $copy["first"][0], "\n";

$ao = new ArrayObject([10, 20, 30]);
$ao->append(40);
echo $ao->count(), "\n";
echo $ao[3], "\n";

$ao = new ArrayObject(["x" => 1, "y" => 2]);
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";

class FilterIter extends ArrayIterator {
    public function __construct(array $arr) {
        parent::__construct(array_filter($arr, fn($v) => $v > 0));
    }
}

$ao = new ArrayObject([1, -2, 3, -4, 5]);
$ao->setIteratorClass("FilterIter");
$result = [];
foreach ($ao as $v) $result[] = $v;
print_r($result);

class CountingIter extends ArrayIterator {
    public static int $count = 0;
    public function current(): mixed {
        self::$count++;
        return parent::current();
    }
}

$ao = new ArrayObject([1, 2, 3]);
$ao->setIteratorClass("CountingIter");
foreach ($ao as $v) ;
echo CountingIter::$count, "\n";

$ao = new ArrayObject(range(1, 5));
$it = $ao->getIterator();
echo $it instanceof ArrayIterator ? "y" : "n", "\n";
echo $it instanceof Iterator ? "y" : "n", "\n";

$it->rewind();
while ($it->valid()) {
    echo $it->key(), "=", $it->current(), " ";
    $it->next();
}
echo "\n";

$ao = new ArrayObject([1, 2, 3, 4, 5]);
$sum = 0;
foreach ($ao as $v) $sum += $v;
echo $sum, "\n";

class Adapter implements IteratorAggregate {
    public function __construct(private ArrayObject $ao) {}
    public function getIterator(): Iterator {
        return $this->ao->getIterator();
    }
}

$wrapped = new Adapter(new ArrayObject(["alpha", "beta", "gamma"]));
foreach ($wrapped as $v) echo $v, " ";
echo "\n";

$ao = new ArrayObject([
    "users" => [
        ["name" => "alice"],
        ["name" => "bob"],
    ],
]);
foreach ($ao["users"] as $u) echo $u["name"], " ";
echo "\n";

$ao = new ArrayObject([1, 2, 3]);
foreach ($ao as $k1 => $v1) {
    foreach ($ao as $k2 => $v2) {
        if ($k1 === $k2) echo "$k1:$v1 ";
    }
}
echo "\n";

$ao = new ArrayObject;
$ao["x"] = 10;
$ao["y"] = 20;
$ao["z"] = 30;
$arr = $ao->getArrayCopy();
print_r($arr);

$it1 = (new ArrayObject([1, 2]))->getIterator();
$it2 = (new ArrayObject([3, 4]))->getIterator();
$appended = new AppendIterator;
$appended->append($it1);
$appended->append($it2);
$result = [];
foreach ($appended as $v) $result[] = $v;
print_r($result);

$nested = new ArrayObject(["x" => new ArrayObject([1, 2, 3])]);
echo $nested["x"]->count(), "\n";
$nested["x"][] = 99;
echo $nested["x"]->count(), "\n";
print_r($nested["x"]->getArrayCopy());
