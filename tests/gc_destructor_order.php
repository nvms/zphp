<?php
// the cycle collector calls the garbage's destructors in the order of php's
// root buffer: a value whose refcount drops to a nonzero count takes the
// next place (or the last one freed), and a collection first moves the
// roots past the count into the holes before it, the last root first

class Node {
    public $self;
    public function __construct(public string $name) {
        $this->self = $this;
    }
    public function __destruct() {
        echo "destruct {$this->name}\n";
    }
}

function roots(): int {
    return gc_status()['roots'];
}

// no holes: buffer order
new Node("a1");
new Node("a2");
new Node("a3");
gc_collect_cycles();

// a live root before them leaves a hole at the front: the last one moves in
$live = new Node("live");
new Node("b1");
new Node("b2");
new Node("b3");
gc_collect_cycles();
echo "--\n";

// two live roots: the last two move into the holes, last first
$live1 = new Node("live1");
$live2 = new Node("live2");
new Node("c1");
new Node("c2");
new Node("c3");
new Node("c4");
gc_collect_cycles();
echo "--\n";

// a place freed by a value that died is reused by the next root
$tmp = new Node("tmp");
$tmp->self = null;
new Node("d1");
unset($tmp);
new Node("d2");
new Node("d3");
gc_collect_cycles();
echo "--\n";

// garbage reached only through a root follows the roots
class Holder {
    public $items = [];
    public $self;
    public function __construct(public string $name) {
        $this->self = $this;
    }
    public function __destruct() {
        echo "destruct {$this->name}\n";
    }
}
class Plain {
    public function __construct(public string $name) {}
    public function __destruct() {
        echo "destruct {$this->name}\n";
    }
}
$h = new Holder("holder");
$h->items[] = new Plain("inner1");
$h->items[] = new Plain("inner2");
unset($h);
new Node("e1");
gc_collect_cycles();
echo "--\n";

// a suspended fiber is destroyed in its place among the garbage
$f = new Fiber(function () use (&$f) {
    $obj = new Plain("fiber local");
    try {
        Fiber::suspend();
    } finally {
        echo "fiber finally\n";
    }
});
$f->start();
$n = new Node("after fiber");
unset($f, $n);
gc_collect_cycles();
echo "--\n";

// roots made by new and by constructor calls, not by passing arguments
echo roots(), "\n";
$c = function () {};
$fiber = new Fiber($c);
echo roots(), "\n";
$ao = new ArrayObject([]);
echo roots(), "\n";
register_shutdown_function($c);
echo roots(), "\n";
var_dump(gc_collect_cycles());

// a WeakMap entry whose value holds its key goes with the garbage in
// buffer order
class Canary extends stdClass {
    public function __construct(public string $name) {}
    public function __destruct() {
        echo "destruct {$this->name}\n";
    }
}
$container = new Canary("container");
$canary = new Canary("canary");
$container->canary = $canary;
$map = new WeakMap();
$map[$canary] = $container;
unset($container, $canary);
gc_collect_cycles();
echo "end\n";
