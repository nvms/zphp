<?php
// public properties iterate in foreach
class P {
    public int $a = 1;
    public string $b = "hello";
    public array $c = [10, 20];
    private int $hidden = 99;
    protected string $prot = "p";
}
$p = new P;
foreach ($p as $k => $v) echo "$k="; echo "\n";
foreach ($p as $k => $v) {
    if (is_array($v)) echo "$k=[", implode(",", $v), "] ";
    else echo "$k=$v ";
}
echo "\n";

// only public visible from outside
$visited = [];
foreach ($p as $k => $v) $visited[] = $k;
print_r($visited); // [a, b, c]

// foreach $this from inside class shows private/protected (architectural - scope-aware vis not wired)

// inherited public properties
class Base {
    public int $base_pub = 10;
    private int $base_priv = 11;
    protected int $base_prot = 12;
}
class Sub extends Base {
    public int $sub_pub = 20;
}
$s = new Sub;
$visited = [];
foreach ($s as $k => $v) $visited[] = "$k=$v";
print_r($visited); // base_pub=10, sub_pub=20

// modify during iteration
class M {
    public int $a = 1;
    public int $b = 2;
    public int $c = 3;
}
$m = new M;
foreach ($m as $k => $v) {
    echo "$k=$v ";
}
echo "\n";

// dynamic properties iterated too
$o = new stdClass;
$o->x = 1;
$o->y = 2;
$o->z = 3;
foreach ($o as $k => $v) echo "$k=$v ";
echo "\n";

// generator yielding from subclass
class GenBase {
    public function items(): Generator {
        yield "base1";
        yield "base2";
    }
}
class GenSub extends GenBase {
    public function items(): Generator {
        yield from parent::items();
        yield "sub1";
        yield "sub2";
    }
}
foreach ((new GenSub)->items() as $v) echo "$v ";
echo "\n";

// yield from generator method
class Counter {
    public function range(int $from, int $to): Generator {
        for ($i = $from; $i <= $to; $i++) yield $i;
    }
}
foreach ((new Counter)->range(1, 5) as $v) echo "$v ";
echo "\n";

// IteratorAggregate
class Bag implements IteratorAggregate {
    private array $items = [];
    public function add($item): void { $this->items[] = $item; }
    public function getIterator(): Iterator {
        return new ArrayIterator($this->items);
    }
}
$b = new Bag;
$b->add("a");
$b->add("b");
$b->add("c");
foreach ($b as $k => $v) echo "$k=$v ";
echo "\n";

// IteratorAggregate returning Generator
class GenBag implements IteratorAggregate {
    private array $data = [];
    public function add($v): void { $this->data[] = $v; }
    public function getIterator(): Generator {
        foreach ($this->data as $k => $v) {
            yield "key_$k" => strtoupper($v);
        }
    }
}
$g = new GenBag;
$g->add("alpha");
$g->add("beta");
foreach ($g as $k => $v) echo "$k=$v ";
echo "\n";

// nested IteratorAggregate
class Tree implements IteratorAggregate {
    private array $children = [];
    public function add(Tree $c): void { $this->children[] = $c; }
    public function __construct(public string $name) {}
    public function getIterator(): Generator {
        yield $this->name;
        foreach ($this->children as $c) yield from $c;
    }
}
$root = new Tree("root");
$a = new Tree("a");
$a->add(new Tree("a1"));
$root->add($a);
$root->add(new Tree("b"));
foreach ($root as $name) echo "$name ";
echo "\n";

// Iterator interface manually
class Range implements Iterator {
    private int $current;
    public function __construct(private int $from, private int $to) {
        $this->current = $from;
    }
    public function current(): int { return $this->current; }
    public function key(): int { return $this->current - $this->from; }
    public function next(): void { $this->current++; }
    public function rewind(): void { $this->current = $this->from; }
    public function valid(): bool { return $this->current <= $this->to; }
}
foreach (new Range(1, 4) as $k => $v) echo "$k=$v ";
echo "\n";

// foreach by reference on object (architectural - object iter snapshot, no writeback)

// foreach over object preserves declaration order
class Order {
    public string $z = "Z";
    public string $a = "A";
    public string $m = "M";
}
foreach (new Order as $k => $v) echo "$k=$v ";
echo "\n";

// IteratorAggregate that throws
class Bad implements IteratorAggregate {
    public function getIterator(): Iterator {
        throw new \RuntimeException("nope");
    }
}
try {
    foreach (new Bad as $v) echo $v;
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "caught:", $e->getMessage(), "\n";
}

// foreach generator twice (must rewind)
$g = (function () {
    yield 1; yield 2;
})();
foreach ($g as $v) echo "$v ";
echo "\n";
try {
    foreach ($g as $v) echo "$v ";
    echo "\n";
} catch (\Exception $e) {
    echo "rewind-exc\n";
}

// count() on Countable
class Coll implements Countable {
    public function count(): int { return 42; }
}
echo count(new Coll), "\n";
