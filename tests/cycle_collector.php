<?php
// Stage 2 cycle collector: gc_collect_cycles() now does the real PHP
// trial-decrement algorithm to find unreachable object cycles that pure
// refcounting can't reclaim. without it `$a->next = $b; $b->next = $a;`
// leaks both objects until end-of-request.
class N
{
    public $next;
    public $id;
    public function __construct($id) { $this->id = $id; }
    public function __destruct() { echo "destruct {$this->id}\n"; }
}

echo "== simple A->B->A cycle ==\n";
$a = new N('A');
$b = new N('B');
$a->next = $b;
$b->next = $a;
unset($a, $b);
echo "before gc\n";
$n = gc_collect_cycles();
echo "collected $n\n";

echo "== self-cycle A->A ==\n";
$x = new N('X');
$x->next = $x;
unset($x);
echo "before gc\n";
$n = gc_collect_cycles();
echo "collected $n\n";

echo "== three-cycle A->B->C->A ==\n";
$a = new N('A1');
$b = new N('B1');
$c = new N('C1');
$a->next = $b;
$b->next = $c;
$c->next = $a;
unset($a, $b, $c);
echo "before gc\n";
$n = gc_collect_cycles();
echo "collected $n\n";

echo "== cycle held by external ref - should NOT collect ==\n";
$hold = new N('HELD');
$peer = new N('PEER');
$hold->next = $peer;
$peer->next = $hold;
$ref = $hold;
unset($hold, $peer);
echo "before gc\n";
$n = gc_collect_cycles();
echo "collected $n (expected 0)\n";
unset($ref);
$n = gc_collect_cycles();
echo "after release: collected $n\n";

echo "== cycle through array ==\n";
class Box
{
    public $items = [];
    public $id;
    public function __construct($id) { $this->id = $id; }
    public function __destruct() { echo "destruct box {$this->id}\n"; }
}
$b1 = new Box('1');
$b2 = new Box('2');
$b1->items[] = $b2;
$b2->items[] = $b1;
unset($b1, $b2);
echo "before gc\n";
$n = gc_collect_cycles();
echo "collected $n\n";
