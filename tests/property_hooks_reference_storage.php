<?php
// Reference getters must mutate their returned storage, not a virtual slot.
class ReferenceStorage {
    public array $data = [];
    public array $items {
        &get { echo "get\n"; return $this->data; }
    }
}
$r = new ReferenceStorage;
$p = 'items';
$r->$p[] = 1;
$r->items[] = 2;
$r->$p['key'] = 3;
$r->items['other'] = 4;
var_dump($r->data, $r->$p);
$copy = $r->data;
$a =& $r->items;
$b =& $r->$p;
$a[] = 5;
$b[] = 6;
$r->$p[] = 7;
var_dump($copy, $r->data, $a, $b);
class NullableReferenceStorage {
    public $data = null;
    public $items { &get { return $this->data; } }
}
$n = new NullableReferenceStorage;
$n->$p[] = 8;
var_dump($n->data);
class ShortReferenceStorage {
    public array $data = [];
    public array $items { &get => $this->data; }
}
$s = new ShortReferenceStorage;
$s->$p[] = 9;
$s->items['key'] = 10;
$alias =& $s->$p;
$alias[] = 11;
var_dump($s->data, $s->items);
