<?php
// the SPL containers' serialized members: references survive the round
// trip, typed properties take only what their type accepts strictly
class Foo extends ArrayObject {
    public int $a = 0;
    public int $b = 0;
    public $plain = 'p';
}

$f = new Foo([1, 2]);
$r = &$f->a;
$f->b = &$r;
$f->b = 1;
echo $s = serialize($f), "\n";
var_dump($u = unserialize($s));
$u->b = 2;
var_dump($u->a, $u->b);

foreach ([
    'O:3:"Foo":4:{i:0;i:0;i:1;a:0:{}i:2;a:2:{s:1:"a";s:2:"10";s:1:"b";i:5;}i:3;N;}',
    'O:3:"Foo":4:{i:0;i:0;i:1;a:0:{}i:2;a:1:{s:1:"b";d:1.0;}i:3;N;}',
    'O:3:"Foo":4:{i:0;i:0;i:1;a:0:{}i:2;a:1:{s:5:"plain";a:0:{}}i:3;N;}',
] as $data) {
    try {
        var_dump(unserialize($data));
    } catch (Throwable $e) {
        echo $e::class, ': ', $e->getMessage(), "\n";
    }
}

class Store extends SplObjectStorage {
    public ?string $name = null;
}
try {
    unserialize('O:5:"Store":3:{i:0;a:0:{}i:1;a:1:{s:4:"name";i:5;}i:2;N;}');
} catch (Throwable $e) {
    echo $e::class, ': ', $e->getMessage(), "\n";
}
$st = new Store;
$st->name = 'x';
var_dump(unserialize(serialize($st))->name);

class Lst extends SplDoublyLinkedList {
    public array $items = [];
    public array $copy = [];
}
$l = new Lst;
$l->push(1);
$l->items = [1];
$l->copy = &$l->items;
$u = unserialize(serialize($l));
$u->copy[] = 2;
var_dump($u->items);
