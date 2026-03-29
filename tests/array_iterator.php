<?php
// covers: ArrayIterator, foreach over ArrayIterator, Iterator protocol, count, ArrayAccess

// basic foreach
$arr = new ArrayIterator(['a', 'b', 'c']);
$result = [];
foreach ($arr as $k => $v) {
    $result[] = "$k:$v";
}
echo implode(',', $result) . "\n"; // 0:a,1:b,2:c

// count
echo count($arr->getArrayCopy()) . "\n"; // 3
echo $arr->count() . "\n"; // 3

// string keys
$arr2 = new ArrayIterator(['x' => 1, 'y' => 2, 'z' => 3]);
$result2 = [];
foreach ($arr2 as $k => $v) {
    $result2[] = "$k=$v";
}
echo implode(',', $result2) . "\n"; // x=1,y=2,z=3

// ArrayAccess
$arr3 = new ArrayIterator([10, 20, 30]);
$arr3[1] = 99;
echo $arr3[1] . "\n"; // 99

// append
$arr3->append(40);
echo $arr3->count() . "\n"; // 4

// manual iteration
$arr4 = new ArrayIterator(['one', 'two', 'three']);
$arr4->rewind();
$manual = [];
while ($arr4->valid()) {
    $manual[] = $arr4->key() . ':' . $arr4->current();
    $arr4->next();
}
echo implode(',', $manual) . "\n"; // 0:one,1:two,2:three

// empty iterator
$empty = new ArrayIterator([]);
$count = 0;
foreach ($empty as $v) { $count++; }
echo $count . "\n"; // 0

// IteratorAggregate via Collection-like pattern
class MyCollection implements IteratorAggregate {
    private $items;
    public function __construct(array $items) { $this->items = $items; }
    public function getIterator(): ArrayIterator {
        return new ArrayIterator($this->items);
    }
}

$coll = new MyCollection(['foo', 'bar', 'baz']);
$result3 = [];
foreach ($coll as $v) {
    $result3[] = $v;
}
echo implode(',', $result3) . "\n"; // foo,bar,baz

// getArrayCopy
$arr5 = new ArrayIterator([1, 2, 3]);
$copy = $arr5->getArrayCopy();
echo implode(',', $copy) . "\n"; // 1,2,3

// offsetExists / offsetUnset
$arr6 = new ArrayIterator(['a' => 1, 'b' => 2]);
echo ($arr6->offsetExists('a') ? 'yes' : 'no') . "\n"; // yes
$arr6->offsetUnset('a');
echo ($arr6->offsetExists('a') ? 'yes' : 'no') . "\n"; // no
echo $arr6->count() . "\n"; // 1
