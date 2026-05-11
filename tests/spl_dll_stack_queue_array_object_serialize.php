<?php
$dll = new SplDoublyLinkedList;
$dll->push("a");
$dll->push("b");
$dll->push("c");

$ser = serialize($dll);
echo strlen($ser) > 0 ? "y" : "n", "\n";

$dll2 = unserialize($ser);
echo $dll2 instanceof SplDoublyLinkedList ? "y" : "n", "\n";
echo $dll2->count(), "\n";
foreach ($dll2 as $v) echo $v, " ";
echo "\n";

$stack = new SplStack;
$stack->push(1);
$stack->push(2);
$stack->push(3);

$ser = serialize($stack);
$stack2 = unserialize($ser);
echo $stack2 instanceof SplStack ? "y" : "n", "\n";
echo $stack2->count(), "\n";
echo $stack2->pop(), " ", $stack2->pop(), " ", $stack2->pop(), "\n";

$queue = new SplQueue;
$queue->enqueue("first");
$queue->enqueue("second");
$queue->enqueue("third");

$ser = serialize($queue);
$queue2 = unserialize($ser);
echo $queue2 instanceof SplQueue ? "y" : "n", "\n";
echo $queue2->dequeue(), " ", $queue2->dequeue(), " ", $queue2->dequeue(), "\n";

$ao = new ArrayObject(["a" => 1, "b" => 2, "c" => 3]);
$ser = serialize($ao);
echo strlen($ser) > 0 ? "y" : "n", "\n";

$ao2 = unserialize($ser);
echo $ao2 instanceof ArrayObject ? "y" : "n", "\n";
echo $ao2["a"], " ", $ao2["b"], " ", $ao2["c"], "\n";
echo count($ao2), "\n";

print_r($ao2->getArrayCopy());

$ao = new ArrayObject([1, 2, [3, 4, [5, 6]]]);
$ser = serialize($ao);
$ao2 = unserialize($ser);
print_r($ao2->getArrayCopy());

$ao = new ArrayObject(["nested" => ["deep" => "value"]]);
$ao2 = unserialize(serialize($ao));
echo $ao2["nested"]["deep"], "\n";

$dll = new SplDoublyLinkedList;
$dll->push(["x", "y"]);
$dll->push((object)["k" => "v"]);
$dll->push(42);

$ser = serialize($dll);
$dll2 = unserialize($ser);
echo $dll2->count(), "\n";
$arr = iterator_to_array($dll2);
print_r($arr[0]);
echo $arr[1]->k, "\n";
echo $arr[2], "\n";

$ao = new ArrayObject([]);
$ser = serialize($ao);
$ao2 = unserialize($ser);
echo $ao2 instanceof ArrayObject ? "y" : "n", "\n";
echo count($ao2), "\n";

$dll = new SplDoublyLinkedList;
echo serialize($dll) !== "" ? "y" : "n", "\n";
$dll2 = unserialize(serialize($dll));
echo $dll2->count(), "\n";

$pq = new SplPriorityQueue;
$pq->insert("low", 1);
$pq->insert("high", 10);
$pq->insert("mid", 5);

$ser = serialize($pq);
$pq2 = unserialize($ser);
echo $pq2 instanceof SplPriorityQueue ? "y" : "n", "\n";
echo $pq2->count(), "\n";

$ao = new ArrayObject([1, 2, 3], ArrayObject::ARRAY_AS_PROPS);
$ao2 = unserialize(serialize($ao));
echo $ao2->getFlags() === $ao->getFlags() ? "y" : "n", "\n";

$dll = new SplDoublyLinkedList;
for ($i = 1; $i <= 5; $i++) $dll->push($i);
$out = serialize($dll);
$res = unserialize($out);
$sum = 0;
foreach ($res as $v) $sum += $v;
echo $sum, "\n";

$ao = new ArrayObject(["x"=>1, "y"=>2, "z"=>3]);
$copy = unserialize(serialize($ao));
$keys = [];
foreach ($copy as $k => $v) $keys[] = "$k=$v";
sort($keys);
print_r($keys);

$stack = new SplStack;
$stack->push("alpha");
$stack->push("beta");
$res = unserialize(serialize($stack));
$out = [];
while (!$res->isEmpty()) $out[] = $res->pop();
print_r($out);

$ao = new ArrayObject([10, 20, 30]);
$ao[] = 40;
$ao[] = 50;
$copy = unserialize(serialize($ao));
echo count($copy), "\n";
echo $copy[3], " ", $copy[4], "\n";

$dll = new SplDoublyLinkedList;
$dll->push("a");
$dll->unshift("z");
$copy = unserialize(serialize($dll));
$out = [];
foreach ($copy as $v) $out[] = $v;
print_r($out);
