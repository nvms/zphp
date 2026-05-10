<?php
$ao = new ArrayObject(["a" => 1, "b" => 2, "c" => 3]);

echo count($ao), "\n";
echo $ao->count(), "\n";

$ao->append("appended");
echo count($ao), "\n";
print_r($ao->getArrayCopy());

$ao->offsetSet("d", 99);
print_r($ao->getArrayCopy());

$ao->offsetUnset("a");
print_r($ao->getArrayCopy());

echo $ao->offsetExists("b") ? "y" : "n", "\n";
echo $ao->offsetExists("zzz") ? "y" : "n", "\n";
echo $ao->offsetGet("b"), "\n";

$ao = new ArrayObject([3, 1, 2]);
$ao->asort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["c" => 1, "a" => 2, "b" => 3]);
$ao->ksort();
print_r($ao->getArrayCopy());

// arsort/krsort not in ArrayObject (architectural - zphp adds, PHP doesn't)

$ao = new ArrayObject([3, 1, 2]);
$ao->uasort(fn($a, $b) => $a - $b);
print_r($ao->getArrayCopy());

$ao = new ArrayObject([3, 1, 2]);
$ao->uksort(fn($a, $b) => $a - $b);
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["item10", "item2", "item1"]);
$ao->natsort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["IMG10", "img2", "Img1"]);
$ao->natcasesort();
print_r($ao->getArrayCopy());

$ao = new ArrayObject([3, 1, 4, 1, 5]);
$ao->asort();
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";

$ao = new ArrayObject(["x" => 1, "y" => 2]);
$it = $ao->getIterator();
foreach ($it as $k => $v) echo "$k=$v ";
echo "\n";

echo get_class($it), "\n";

$ao = new ArrayObject([1, 2, 3]);
$ao[] = 99;
print_r($ao->getArrayCopy());
$ao[100] = "new";
print_r($ao->getArrayCopy());

echo isset($ao[0]) ? "y" : "n", "\n";
echo isset($ao[999]) ? "y" : "n", "\n";

unset($ao[0]);
echo $ao->offsetExists(0) ? "y" : "n", "\n";

$ao = new ArrayObject(["x" => 10, "y" => 20], ArrayObject::ARRAY_AS_PROPS);
echo $ao->x, "\n";
echo $ao->y, "\n";

$ao->z = 30;
echo $ao["z"], "\n";

$ao = new ArrayObject([1, 2, 3]);
$ao->setIteratorClass("ArrayIterator");
$it = $ao->getIterator();
echo get_class($it), "\n";

$copy = $ao->getArrayCopy();
$copy[] = 999;
echo count($ao), "/", count($copy), "\n";

$ao = new ArrayObject([1, 2, 3]);
echo count($ao), "\n";
$ao->exchangeArray(["a", "b"]);
print_r($ao->getArrayCopy());

$ao = new ArrayObject(["a" => 1]);
$old = $ao->exchangeArray(["b" => 2, "c" => 3]);
print_r($old);
print_r($ao->getArrayCopy());

$ao = new ArrayObject([1, 2, 3]);
foreach ($ao as $k => $v) {
    echo "$k=$v ";
}
echo "\n";

$ao = new ArrayObject([10, 20, 30]);
foreach ($ao as $i => $v) echo "$i=$v ";
echo "\n";

$ao = new ArrayObject(["a" => "alpha", "b" => "beta"]);
foreach ($ao as $k => $v) echo "$k:$v ";
echo "\n";

$ao = new ArrayObject([1, 2, 3]);
$ao2 = clone $ao;
$ao2->append(99);
echo count($ao), "/", count($ao2), "\n";

$ao = new ArrayObject(["a" => 1]);
$ao["b"] = 2;
$ao->append(3);
print_r($ao->getArrayCopy());

class Holder extends ArrayObject {
    public function dump(): array {
        return $this->getArrayCopy();
    }
}
$h = new Holder(["x" => 1, "y" => 2]);
$h["z"] = 3;
print_r($h->dump());

// (object)cast numeric-prop access (architectural)

var_dump($ao instanceof ArrayObject);
var_dump($ao instanceof Countable);
var_dump($ao instanceof IteratorAggregate);
var_dump($ao instanceof ArrayAccess);
