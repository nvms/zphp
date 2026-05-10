<?php
// SplStack clone (deep copy of internal array)
$s = new SplStack();
$s->push(1); $s->push(2); $s->push(3);

$copy = clone $s;
$s->pop();
echo $s->count(), "|", $copy->count(), "\n"; // 2|3
foreach ($copy as $v) echo "$v ";
echo "\n"; // 3 2 1 (LIFO)

// SplQueue clone
$q = new SplQueue();
$q->enqueue("a"); $q->enqueue("b"); $q->enqueue("c");

$copy = clone $q;
$q->dequeue();
echo $q->count(), "|", $copy->count(), "\n"; // 2|3
foreach ($copy as $v) echo "$v ";
echo "\n";

// SplDoublyLinkedList offsetGet on bad index
$l = new SplDoublyLinkedList();
$l->push("a"); $l->push("b");

echo $l[0], ":", $l[1], "\n";
try { echo $l[5], "\n"; } catch (\OutOfRangeException $e) { echo "oor\n"; }
try { echo $l[-1], "\n"; } catch (\OutOfRangeException $e) { echo "oor-neg\n"; }

// offsetSet
$l[0] = "X";
echo $l[0], "\n";

// offsetUnset
unset($l[0]);
echo $l->count(), "\n";

// SplObjectStorage addAll/removeAll
$s1 = new SplObjectStorage();
$s2 = new SplObjectStorage();
$o1 = new stdClass; $o1->v = 1;
$o2 = new stdClass; $o2->v = 2;
$o3 = new stdClass; $o3->v = 3;
$s1[$o1] = "a";
$s1[$o2] = "b";
$s2[$o2] = "B"; // override
$s2[$o3] = "c";

$s1->addAll($s2);
echo $s1->count(), "\n"; // 3
echo $s1[$o1], ":", $s1[$o2], ":", $s1[$o3], "\n"; // a:B:c

// removeAll
$rm = new SplObjectStorage();
$rm[$o2] = null;
$s1->removeAll($rm);
echo $s1->count(), "\n"; // 2
echo isset($s1[$o2]) ? "y" : "n", "\n"; // n

// removeAllExcept
$s1->removeAllExcept($rm);  // (rm has $o2, but $o2 already removed)
echo $s1->count(), "\n"; // 0

// ArrayIterator append
$ai = new ArrayIterator(["a", "b"]);
$ai->append("c");
print_r($ai->getArrayCopy());

$ai = new ArrayIterator(["x" => 1]);
$ai->append("appended");
print_r($ai->getArrayCopy()); // ["x"=>1, 0=>"appended"]

// ArrayObject offsetExists vs isset
$ao = new ArrayObject();
$ao["a"] = null;
$ao["b"] = 1;

echo $ao->offsetExists("a") ? "y" : "n", "|"; // y (key present)
echo $ao->offsetExists("b") ? "y" : "n", "|"; // y
echo $ao->offsetExists("c") ? "y" : "n", "\n"; // n

echo isset($ao["a"]) ? "y" : "n", "|"; // n (null value)
echo isset($ao["b"]) ? "y" : "n", "|"; // y
echo isset($ao["c"]) ? "y" : "n", "\n"; // n

// ArrayObject getArrayCopy
print_r($ao->getArrayCopy());

// ArrayObject ARRAY_AS_PROPS
$ao = new ArrayObject(["foo" => 1, "bar" => 2], ArrayObject::ARRAY_AS_PROPS);
echo $ao->foo, "|", $ao->bar, "\n";
$ao->baz = 3;
echo $ao["baz"], "\n";

// Iterator throw in current
class B implements Iterator {
    private int $i = 0;
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return $this->i < 3; }
    public function current(): mixed {
        if ($this->i === 1) throw new RuntimeException("at $this->i");
        return $this->i;
    }
    public function key(): mixed { return $this->i; }
    public function next(): void { $this->i++; }
}
try {
    foreach (new B as $v) echo "$v ";
    echo "no\n";
} catch (\RuntimeException $e) { echo "caught:", $e->getMessage(), "\n"; }

// SplObjectStorage::offsetUnset on missing (should be no-op)
$s = new SplObjectStorage();
$o = new stdClass;
unset($s[$o]); // no-op, no error
echo $s->count(), "\n";

// SplFixedArray clone (deep copy)
$fa = new SplFixedArray(3);
$fa[0] = "a"; $fa[1] = "b"; $fa[2] = "c";
$copy = clone $fa;
$fa[0] = "X";
echo $fa[0], "|", $copy[0], "\n"; // X|a
