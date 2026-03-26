<?php

// basic __clone
class Node {
    public $value;
    public $child = null;

    public function __construct($v) { $this->value = $v; }

    public function __clone() {
        if ($this->child !== null) {
            $this->child = clone $this->child;
        }
    }
}

$a = new Node("root");
$a->child = new Node("leaf");

$b = clone $a;
$b->child->value = "modified";

echo $a->child->value . "\n";
echo $b->child->value . "\n";

// __clone with array of objects
class Container {
    public array $items = [];

    public function __clone() {
        foreach ($this->items as $k => $item) {
            if (is_object($item)) {
                $this->items[$k] = clone $item;
            }
        }
    }
}

class Item { public $name; public function __construct($n) { $this->name = $n; } }

$c = new Container();
$c->items[] = new Item("first");
$c->items[] = new Item("second");

$d = clone $c;
$d->items[0]->name = "changed";

echo $c->items[0]->name . "\n";
echo $d->items[0]->name . "\n";

// __clone modifying properties
class Counter {
    public int $id;
    public int $cloneCount = 0;
    private static int $nextId = 1;

    public function __construct() { $this->id = self::$nextId++; }

    public function __clone() {
        $this->id = self::$nextId++;
        $this->cloneCount++;
    }
}

$orig = new Counter();
$copy1 = clone $orig;
$copy2 = clone $copy1;

echo $orig->id . "," . $orig->cloneCount . "\n";
echo $copy1->id . "," . $copy1->cloneCount . "\n";
echo $copy2->id . "," . $copy2->cloneCount . "\n";

echo "done\n";
