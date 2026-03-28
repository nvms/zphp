<?php

// Iterator interface
class Range implements Iterator {
    private int $current;

    public function __construct(
        private int $start,
        private int $end
    ) {
        $this->current = $start;
    }

    public function current(): int {
        return $this->current;
    }

    public function key(): int {
        return $this->current - $this->start;
    }

    public function next(): void {
        $this->current++;
    }

    public function rewind(): void {
        $this->current = $this->start;
    }

    public function valid(): bool {
        return $this->current <= $this->end;
    }
}

$range = new Range(1, 5);
$items = [];
foreach ($range as $key => $value) {
    $items[] = "$key:$value";
}
echo implode(",", $items) . "\n";

// rewind works - iterate again
$items2 = [];
foreach ($range as $value) {
    $items2[] = $value;
}
echo implode(",", $items2) . "\n";

// instanceof
echo ($range instanceof Iterator) ? "is Iterator" : "not Iterator";
echo "\n";

// SimpleArrayIterator - simple Iterator over an array
class SimpleArrayIterator implements Iterator {
    private int $pos = 0;
    private array $keys;

    public function __construct(private array $data) {
        $this->keys = array_keys($data);
    }

    public function current(): mixed {
        return $this->data[$this->keys[$this->pos]];
    }

    public function key(): mixed {
        return $this->keys[$this->pos];
    }

    public function next(): void {
        $this->pos++;
    }

    public function rewind(): void {
        $this->pos = 0;
    }

    public function valid(): bool {
        return $this->pos < count($this->keys);
    }
}

// IteratorAggregate
class Collection implements IteratorAggregate {
    private array $items;

    public function __construct(array $items) {
        $this->items = $items;
    }

    public function getIterator(): SimpleArrayIterator {
        return new SimpleArrayIterator($this->items);
    }
}

$col = new Collection(["a" => 1, "b" => 2, "c" => 3]);
$pairs = [];
foreach ($col as $key => $value) {
    $pairs[] = "$key=$value";
}
echo implode(",", $pairs) . "\n";

echo ($col instanceof IteratorAggregate) ? "is IteratorAggregate" : "not";
echo "\n";

// empty iterator
$empty = new Range(5, 3);
$count = 0;
foreach ($empty as $v) {
    $count++;
}
echo "empty: $count\n";

echo "done\n";
