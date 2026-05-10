<?php
class Box {
    public int $size = 10;
    public string $color = "red";
}

$b = new Box;
$c = clone $b;
$c->size = 99;
echo $b->size, " ", $c->size, "\n"; // 10 99 (separate)

$c->color = "blue";
echo $b->color, " ", $c->color, "\n";

// type preserved
echo get_class($c), "\n";
var_dump($c instanceof Box);

// shallow clone: object props share reference
class Inner {
    public int $n = 1;
}
class Outer {
    public Inner $inner;
    public function __construct() {
        $this->inner = new Inner;
    }
}

$o1 = new Outer;
$o2 = clone $o1;
$o2->inner->n = 99;
// shallow: both should see the change
echo $o1->inner->n, " ", $o2->inner->n, "\n"; // 99 99

// deep via __clone
class DeepOuter {
    public Inner $inner;
    public function __construct() {
        $this->inner = new Inner;
    }
    public function __clone(): void {
        $this->inner = clone $this->inner;
    }
}

$d1 = new DeepOuter;
$d2 = clone $d1;
$d2->inner->n = 42;
echo $d1->inner->n, " ", $d2->inner->n, "\n"; // 1 42

// array property is value-copied (PHP arrays are value type)
class ArrHolder {
    public array $items = [1, 2, 3];
}

$a1 = new ArrHolder;
$a2 = clone $a1;
$a2->items[] = 99;
print_r($a1->items); // [1, 2, 3]
print_r($a2->items); // [1, 2, 3, 99]

// modify nested object inside array property - shallow shares
class WithArrOfObj {
    public array $boxes;
    public function __construct() {
        $this->boxes = [new Box, new Box];
    }
}
$w1 = new WithArrOfObj;
$w2 = clone $w1;
$w2->boxes[0]->size = 555;
echo $w1->boxes[0]->size, " ", $w2->boxes[0]->size, "\n"; // shallow: 555 555

// __clone is called
class Tracked {
    public static int $count = 0;
    public function __clone(): void {
        self::$count++;
    }
}
$t = new Tracked;
$c = clone $t;
$c2 = clone $c;
echo Tracked::$count, "\n"; // 2

// equal but not identical
$b1 = new Box;
$b2 = clone $b1;
var_dump($b1 == $b2);   // true (same class, same props)
var_dump($b1 === $b2);  // false (different instances)

// modifying one breaks ==
$b2->size = 99;
var_dump($b1 == $b2); // false

// clone with __construct doesn't re-run
class WithCtor {
    public int $created = 0;
    public function __construct() {
        $this->created++;
    }
}

$o = new WithCtor;
echo $o->created, "\n"; // 1
$c = clone $o;
echo $c->created, "\n"; // 1 (not re-incremented)

// clone keeps private/protected
class Visibility {
    public string $pub = "p";
    protected string $prot = "pr";
    private string $priv = "pv";
    public function dump(): string {
        return "$this->pub/$this->prot/$this->priv";
    }
}
$v = new Visibility;
$c = clone $v;
echo $c->dump(), "\n";

// dynamic property cloned
$d = new stdClass;
$d->x = 1;
$d->y = "hi";
$c = clone $d;
echo $c->x, "/", $c->y, "\n";
$c->x = 99;
echo $d->x, "/", $c->x, "\n";

// clone ArrayObject
$ao = new ArrayObject([1, 2, 3]);
$ao2 = clone $ao;
$ao2[] = 99;
echo count($ao), "/", count($ao2), "\n"; // 3/4

// clone SplStack
$s = new SplStack;
$s->push(1);
$s->push(2);
$s2 = clone $s;
$s2->push(99);
echo count($s), "/", count($s2), "\n";

// __clone with this modifications affects only the new copy
class Modified {
    public string $tag = "orig";
    public array $list = [1, 2];
    public function __clone(): void {
        $this->tag = "cloned";
        $this->list[] = 99;
    }
}
$m = new Modified;
$c = clone $m;
echo $m->tag, "/", $c->tag, "\n"; // orig/cloned
print_r($m->list);
print_r($c->list);

// chained clone
$b1 = new Box;
$b1->size = 5;
$b2 = clone clone $b1;
echo $b2->size, "\n"; // 5

// clone in expression
function clonefn(Box $b): Box { return clone $b; }
$bn = clonefn(new Box);
echo $bn->size, "\n";

// clone returns new instance
$b = new Box;
echo (clone $b) === $b ? "same\n" : "diff\n"; // diff

// clone with readonly
class RO {
    public function __construct(public readonly int $x) {}
}
$r1 = new RO(5);
$r2 = clone $r1;
echo $r2->x, "\n";

// PHP 8.3+ withProperty() / clone with - skip, only available in PHP 8.3+

// SplObjectStorage clone
$s = new SplObjectStorage;
$o = new stdClass;
$s[$o] = "data";
$s2 = clone $s;
echo count($s2), " ", $s2[$o], "\n";
unset($s2[$o]);
echo count($s), "/", count($s2), "\n"; // 1/0

// clone objects in array_map
$boxes = [new Box, new Box, new Box];
$cloned = array_map(fn($b) => clone $b, $boxes);
$cloned[0]->size = 100;
echo $boxes[0]->size, " ", $cloned[0]->size, "\n";

// clone preserves attributes/static
class WithStatic {
    public static int $shared = 0;
    public int $instance = 0;
}
WithStatic::$shared = 5;
$o = new WithStatic;
$o->instance = 7;
$c = clone $o;
echo $c->instance, " ", WithStatic::$shared, "\n";
$c->instance = 99;
echo $o->instance, " ", $c->instance, "\n";
