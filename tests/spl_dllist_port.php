<?php
// SplDoublyLinkedList, SplQueue and SplStack as php's spl_dllist has them

function show($label, $f) {
    try {
        $r = $f();
        echo $label, ': ';
        var_dump($r);
    } catch (Throwable $e) {
        echo $label, ': ', get_class($e), ': ', $e->getMessage(), "\n";
    }
}

$l = new SplDoublyLinkedList();
show('pop empty', fn() => $l->pop());
show('shift empty', fn() => $l->shift());
show('top empty', fn() => $l->top());
show('bottom empty', fn() => $l->bottom());
show('current empty', fn() => $l->current());
foreach ([1, 2, 3, 4] as $v) $l->push($v);
$l->unshift(0);
show('count', fn() => count($l));
show('offsetGet 2', fn() => $l[2]);
show('offsetGet "1"', fn() => $l["1"]);
show('offsetGet "x"', fn() => $l->offsetGet("x"));
show('offsetGet []', fn() => $l->offsetGet([]));
show('offsetGet 9', fn() => $l[9]);
show('offsetExists -1', fn() => isset($l[-1]));
show('offsetUnset 9', function () use ($l) { unset($l[9]); });
show('offsetSet 9', function () use ($l) { $l[9] = 1; });
show('add 9', fn() => $l->add(9, 'x'));
show('add [] ', fn() => $l->add([], 'x'));
$l->add(1, 'a');
$l->add(6, 'end');
$l[] = 'appended';
unset($l[0]);
var_dump($l);

echo "-- iteration\n";
$l->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO);
foreach ($l as $k => $v) echo "$k=>$v\n";
$l->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO);
foreach ($l as $k => $v) {
    echo "$k=>$v\n";
    foreach ($l as $k2 => $v2) echo "  $k2=>$v2\n";
}
$l->rewind();
$l->next();
echo $l->key(), ' ', $l->current(), "\n";
$l->prev();
echo $l->key(), ' ', $l->current(), "\n";
$l->pop();
$l->rewind();
while ($l->valid()) {
    echo $l->key(), ':', $l->current(), ' ';
    $l->next();
}
echo "\n";

echo "-- delete mode\n";
$d = new SplDoublyLinkedList();
foreach (range(1, 5) as $v) $d->push($v);
$d->setIteratorMode(SplDoublyLinkedList::IT_MODE_DELETE);
foreach ($d as $k => $v) echo "$k=>$v ";
echo count($d), "\n";
foreach (range(1, 5) as $v) $d->push($v);
$d->setIteratorMode(SplDoublyLinkedList::IT_MODE_DELETE | SplDoublyLinkedList::IT_MODE_LIFO);
foreach ($d as $k => $v) echo "$k=>$v ";
echo count($d), "\n";

echo "-- queue and stack\n";
$q = new SplQueue();
$q->enqueue('a');
$q->enqueue('b');
$q[] = 'c';
echo $q->dequeue(), $q->dequeue(), count($q), "\n";
show('queue mode', fn() => $q->setIteratorMode(SplDoublyLinkedList::IT_MODE_LIFO));
show('queue mode keep', fn() => $q->setIteratorMode(SplDoublyLinkedList::IT_MODE_DELETE));
var_dump($q->getIteratorMode());
$s = new SplStack();
foreach ([1, 2, 3] as $v) $s->push($v);
foreach ($s as $k => $v) echo "$k=>$v ";
echo "\n";
show('stack top', fn() => $s->top());
show('stack [0]', fn() => $s[0]);
show('stack mode', fn() => $s->setIteratorMode(SplDoublyLinkedList::IT_MODE_FIFO));
var_dump($s);

echo "-- clone and serialization\n";
$c = clone $s;
$c->push(4);
var_dump(count($s), count($c));
$ser = serialize($s);
echo $ser, "\n";
var_dump(unserialize($ser));
echo $s->serialize(), "\n";
$u = new SplDoublyLinkedList();
$u->unserialize('i:6;:s:1:"x";:i:2;');
var_dump($u);
show('unserialize bad', fn() => $u->unserialize('i:6;:s:1:"x";:i'));
$payload = 'i:0;:i:1;:i:2;';
var_dump(unserialize('C:19:"SplDoublyLinkedList":' . strlen($payload) . ':{' . $payload . '}'));
show('__unserialize bad', fn() => (new SplDoublyLinkedList)->__unserialize([1, 2]));
var_dump($s->__serialize());

class MyList extends SplDoublyLinkedList {
    public $extra = 'x';
    public function count(): int { return 42; }
}
$m = new MyList();
var_dump($m->isEmpty(), count($m));
$m->push(1);
var_dump(unserialize(serialize($m)));

try {
    foreach ($l as &$ref) {}
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
