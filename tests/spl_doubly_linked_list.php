<?php
// covers: SplDoublyLinkedList - push, pop, shift, unshift, top, bottom, count,
//         isEmpty, iterator (FIFO/LIFO), ArrayAccess, add, toArray

$dll = new SplDoublyLinkedList();

// empty state
echo $dll->count() . "\n"; // 0
echo ($dll->isEmpty() ? "true" : "false") . "\n"; // true

// push/pop (tail operations)
$dll->push("a");
$dll->push("b");
$dll->push("c");
echo $dll->count() . "\n"; // 3
echo $dll->top() . "\n"; // c
echo $dll->bottom() . "\n"; // a
echo $dll->pop() . "\n"; // c
echo $dll->count() . "\n"; // 2

// unshift/shift (head operations)
$dll->unshift("z");
echo $dll->bottom() . "\n"; // z
echo $dll->shift() . "\n"; // z
echo $dll->count() . "\n"; // 2

// FIFO iteration (default)
$dll2 = new SplDoublyLinkedList();
$dll2->push(10);
$dll2->push(20);
$dll2->push(30);
$result = [];
for ($dll2->rewind(); $dll2->valid(); $dll2->next()) {
    $result[] = $dll2->current();
}
echo implode(",", $result) . "\n"; // 10,20,30

// LIFO iteration
$dll2->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO);
$result = [];
for ($dll2->rewind(); $dll2->valid(); $dll2->next()) {
    $result[] = $dll2->current();
}
echo implode(",", $result) . "\n"; // 30,20,10

// ArrayAccess
$dll3 = new SplDoublyLinkedList();
$dll3->push("x");
$dll3->push("y");
$dll3->push("z");
echo $dll3[1] . "\n"; // y
$dll3[1] = "Y";
echo $dll3[1] . "\n"; // Y
echo (isset($dll3[2]) ? "true" : "false") . "\n"; // true
echo (isset($dll3[5]) ? "true" : "false") . "\n"; // false
unset($dll3[1]);
echo $dll3->count() . "\n"; // 2

// add (insert at index)
$dll4 = new SplDoublyLinkedList();
$dll4->push("a");
$dll4->push("c");
$dll4->add(1, "b");
$arr = [];
for ($dll4->rewind(); $dll4->valid(); $dll4->next()) {
    $arr[] = $dll4->current();
}
echo implode(",", $arr) . "\n"; // a,b,c

// offsetSet with null key (append)
$dll5 = new SplDoublyLinkedList();
$dll5[] = "first";
$dll5[] = "second";
echo $dll5->count() . "\n"; // 2
echo $dll5[0] . "\n"; // first

echo "DONE\n";
