<?php
class A {
    public int $x = 1;
}

$a = new A;
$b = clone $a;
$b->x = 99;
echo $a->x, " ", $b->x, "\n";
echo $a === $b ? "same" : "diff", "\n";

class Inner {
    public int $v = 10;
}

class Outer {
    public Inner $inner;
    public function __construct() { $this->inner = new Inner; }
}

$o1 = new Outer;
$o2 = clone $o1;
$o2->inner->v = 99;
echo "shared:", $o1->inner->v, " ", $o2->inner->v, "\n";
echo $o1->inner === $o2->inner ? "same-ref" : "diff-ref", "\n";

class WithDeepClone {
    public Inner $inner;
    public function __construct() { $this->inner = new Inner; }
    public function __clone(): void {
        $this->inner = clone $this->inner;
    }
}

$d1 = new WithDeepClone;
$d2 = clone $d1;
$d2->inner->v = 99;
echo "deep:", $d1->inner->v, " ", $d2->inner->v, "\n";
echo $d1->inner === $d2->inner ? "same-ref" : "diff-ref", "\n";

class WithArr {
    public array $data = [1, 2, 3];
    public array $nested = [[1, 2], [3, 4]];
}

$a1 = new WithArr;
$a2 = clone $a1;
$a2->data[] = 99;
print_r($a1->data);
print_r($a2->data);

$a1 = new WithArr;
$a2 = clone $a1;
$a2->nested[0][] = 99;
print_r($a1->nested);
print_r($a2->nested);

class CloneCounter {
    public static int $count = 0;
    public function __clone(): void {
        self::$count++;
    }
}
$o = new CloneCounter;
clone $o;
clone $o;
clone $o;
echo CloneCounter::$count, "\n";

class WithStr {
    public string $name = "alice";
}
$s1 = new WithStr;
$s2 = clone $s1;
$s2->name = "bob";
echo $s1->name, " ", $s2->name, "\n";

class WithList {
    public array $items = [];
    public function add(string $x): void {
        $this->items[] = $x;
    }
}
$l1 = new WithList;
$l1->add("a");
$l1->add("b");
$l2 = clone $l1;
$l2->add("c");
print_r($l1->items);
print_r($l2->items);

class Counter {
    public int $n = 0;
    public function __clone(): void {
        $this->n = 100;
    }
}
$c1 = new Counter;
$c1->n = 5;
$c2 = clone $c1;
echo $c1->n, " ", $c2->n, "\n";

class WithCtor {
    public string $tag;
    public function __construct(string $t) {
        $this->tag = $t;
    }
}
$w1 = new WithCtor("hello");
$w2 = clone $w1;
echo $w1->tag, " ", $w2->tag, "\n";
$w2->tag = "world";
echo $w1->tag, " ", $w2->tag, "\n";

class CloneChain {
    public array $log = [];
    public function __clone(): void {
        $this->log[] = "cloned";
    }
}
$c1 = new CloneChain;
$c1->log[] = "init";
$c2 = clone $c1;
$c3 = clone $c2;
print_r($c1->log);
print_r($c2->log);
print_r($c3->log);

class Holder {
    public ?self $next = null;
}
$h1 = new Holder;
$h1->next = new Holder;
$h2 = clone $h1;
echo $h1->next === $h2->next ? "shared-next" : "diff-next", "\n";

class DeepHolder {
    public ?self $next = null;
    public function __clone(): void {
        if ($this->next !== null) {
            $this->next = clone $this->next;
        }
    }
}
$h1 = new DeepHolder;
$h1->next = new DeepHolder;
$h2 = clone $h1;
echo $h1->next === $h2->next ? "shared-next" : "diff-next", "\n";

class ImmTime {
    public readonly string $tag;
    public function __construct(string $t) { $this->tag = $t; }
}

$imm = new ImmTime("t");
$copy = clone $imm;
echo $imm->tag, " ", $copy->tag, "\n";
echo $imm === $copy ? "same" : "diff", "\n";
try { $copy->tag = "x"; } catch (\Error $e) { echo "ro\n"; }

class Vec {
    public function __construct(public readonly int $x, public readonly int $y) {}
}

$v1 = new Vec(3, 4);
$v2 = clone $v1;
echo $v1->x, ",", $v1->y, " | ", $v2->x, ",", $v2->y, "\n";
echo $v1 === $v2 ? "same" : "diff", "\n";

class WithObjArr {
    public array $items = [];
}
$o = new WithObjArr;
$o->items[] = new Inner;
$o->items[0]->v = 50;
$o2 = clone $o;
echo $o->items[0] === $o2->items[0] ? "shared-obj-in-arr" : "diff-obj-in-arr", "\n";
$o2->items[0]->v = 99;
echo $o->items[0]->v, " ", $o2->items[0]->v, "\n";

class CallsClone {
    public Inner $i;
    public function __construct() { $this->i = new Inner; }
    public function copy(): self {
        return clone $this;
    }
}
$obj = new CallsClone;
$copy = $obj->copy();
echo $obj->i === $copy->i ? "shared" : "diff", "\n";
