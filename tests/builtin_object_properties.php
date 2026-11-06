<?php
// built-in classes show the properties php shows for each purpose, never the
// state zphp keeps for them: ArrayObject's storage for (array), var_export and
// json_encode and as a private property in print_r, the SPL containers'
// private debug properties, and a user's own "__" properties as declared

class Bag extends ArrayObject { public $label = 'bag'; protected $__mine = 1; }
class Plain { public $__x = 1; private $__y = 2; }

$values = [
    new ArrayObject([1, 'k' => 2]),
    new ArrayObject(['a' => 1], ArrayObject::STD_PROP_LIST),
    new ArrayIterator([3, 4]),
    new Bag(['x' => 'y']),
    new Plain,
];
$queue = new SplQueue; $queue[] = 'q';
$stack = new SplStack; $stack->push(1); $stack->push(2);
$heap = new SplMinHeap; foreach ([5, 1, 3, 2] as $n) $heap->insert($n);
$pq = new SplPriorityQueue; $pq->insert('low', 1); $pq->insert('high', 9); $pq->insert('mid', 5);
$fixed = new SplFixedArray(3); $fixed[1] = 'one';
$storage = new SplObjectStorage; $storage[new Plain] = 'info';
array_push($values, $queue, $stack, $heap, $pq, $fixed, $storage, new SplDoublyLinkedList);

foreach ($values as $v) {
    echo get_class($v), "\n";
    print_r($v);
    echo "\n";
    var_export($v);
    echo "\n";
    var_dump(json_encode($v), (array)$v, get_object_vars($v));
    foreach ($v as $k => $item) echo "  $k => ", is_scalar($item) ? $item : gettype($item), "\n";
}
