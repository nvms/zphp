<?php
// cycles that pass through a property bound to a reference

$a = new stdClass();
$a->a = array();
$a->a[0] = new stdClass();
$a->a[0]->a = $a;
$a->a[1] = &$a->a;
var_dump(gc_collect_cycles());
unset($a);
var_dump(gc_collect_cycles());

// the same cycle with a variable still bound to the reference stays
$b = new stdClass();
$b->list = [];
$b->list[0] = $b;
$b->list[1] = &$b->list;
$keep = &$b->list;
unset($b);
var_dump(gc_collect_cycles());
var_dump(count($keep));
unset($keep);
var_dump(gc_collect_cycles());

class Holder {
    public $self;
    public $items;
    function __destruct() {
        echo "destruct\n";
        unset($this->items);
    }
}
$h = new Holder;
$h->self = $h;
$h->items = [];
$h->items[] = &$h->items;
$h->items[] = $h;
var_dump(gc_collect_cycles());
unset($h);
var_dump(gc_collect_cycles());

// a property reference to an outside variable keeps the cycle alive
$outside = [];
$o = new stdClass();
$o->r = &$outside;
$outside[] = $o;
unset($o);
var_dump(gc_collect_cycles());
var_dump(count($outside));
