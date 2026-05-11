<?php
print_r(range(1, 5));
print_r(range(5, 1));
print_r(range(0, 10, 2));
print_r(range(1.0, 3.0, 0.5));
print_r(range("a", "e"));
print_r(range("a", "j", 2));
print_r(range(-3, 3));

echo iterator_count(new ArrayIterator([1, 2, 3, 4, 5])), "\n";
echo iterator_count(new ArrayIterator([])), "\n";
echo iterator_count(new ArrayIterator(["a", "b"])), "\n";

function gen() { yield 1; yield 2; yield 3; }
echo iterator_count(gen()), "\n";

function infinite() {
    $i = 0;
    while (true) yield $i++;
}

$g = infinite();
$first = [];
foreach ($g as $v) {
    $first[] = $v;
    if (count($first) >= 5) break;
}
print_r($first);

$results = [];
iterator_apply(
    new ArrayIterator([1, 2, 3]),
    function ($it) use (&$results) {
        $results[] = $it->current() * 10;
        return true;
    },
    [new ArrayIterator([1, 2, 3])]
);
print_r($results);

class MyCollection implements IteratorAggregate, Countable {
    public function __construct(private array $items) {}
    public function getIterator(): ArrayIterator {
        return new ArrayIterator($this->items);
    }
    public function count(): int { return count($this->items); }
}

$c = new MyCollection([10, 20, 30, 40]);
echo iterator_count($c), "\n";
echo count($c), "\n";

$result = iterator_to_array($c);
print_r($result);

class FilterAdapter implements IteratorAggregate {
    public function __construct(private iterable $inner, private $filter) {}
    public function getIterator(): Generator {
        foreach ($this->inner as $k => $v) {
            if (($this->filter)($v)) yield $k => $v;
        }
    }
}

$nums = new ArrayIterator([1, 2, 3, 4, 5, 6]);
$evens = new FilterAdapter($nums, fn($x) => $x % 2 === 0);
$result = iterator_to_array($evens);
print_r($result);

class MapAdapter implements IteratorAggregate {
    public function __construct(private iterable $inner, private $fn) {}
    public function getIterator(): Generator {
        foreach ($this->inner as $k => $v) {
            yield $k => ($this->fn)($v);
        }
    }
}

$doubled = new MapAdapter(new ArrayIterator([1, 2, 3]), fn($x) => $x * 2);
foreach ($doubled as $k => $v) echo "$k=$v ";
echo "\n";

$composed = new FilterAdapter(
    new MapAdapter(new ArrayIterator([1, 2, 3, 4, 5]), fn($x) => $x * 10),
    fn($v) => $v > 25
);
print_r(iterator_to_array($composed));

class TakeAdapter implements IteratorAggregate {
    public function __construct(private iterable $inner, private int $n) {}
    public function getIterator(): Generator {
        $count = 0;
        foreach ($this->inner as $k => $v) {
            if ($count >= $this->n) break;
            yield $k => $v;
            $count++;
        }
    }
}

$infinite_gen = function () {
    $i = 0;
    while (true) yield $i++;
};
$take5 = new TakeAdapter($infinite_gen(), 5);
print_r(iterator_to_array($take5));

class RangeAggregate implements IteratorAggregate {
    public function __construct(private int $start, private int $end) {}
    public function getIterator(): Generator {
        for ($i = $this->start; $i <= $this->end; $i++) yield $i;
    }
}

$r = new RangeAggregate(1, 5);
$sum = 0;
foreach ($r as $v) $sum += $v;
echo $sum, "\n";

echo iterator_count(new RangeAggregate(1, 10)), "\n";

$values = [];
foreach (range(1, 10) as $v) $values[] = $v;
echo count($values), "\n";
echo array_sum($values), "\n";

function rangeGen(int $start, int $end): Generator {
    for ($i = $start; $i <= $end; $i++) yield $i;
}

print_r(iterator_to_array(rangeGen(5, 10)));

print_r(range(0, 0));
print_r(range("a", "a"));

print_r(range(1, 5, 0.5));

print_r(range(10, 1, 3));
print_r(range(1, 10, 3));

echo iterator_count(new ArrayIterator(array_fill(0, 100, "x"))), "\n";

$nested = new MyCollection([
    new MyCollection([1, 2]),
    new MyCollection([3, 4]),
]);

$flat = [];
foreach ($nested as $sub) {
    foreach ($sub as $v) $flat[] = $v;
}
print_r($flat);

class KeyValueAggregate implements IteratorAggregate {
    public function __construct(private array $data) {}
    public function getIterator(): ArrayIterator {
        return new ArrayIterator($this->data);
    }
}

$kv = new KeyValueAggregate(["a" => 1, "b" => 2, "c" => 3]);
foreach ($kv as $k => $v) echo "$k=$v ";
echo "\n";

print_r(iterator_to_array($kv));

class CounterAggregate implements IteratorAggregate {
    public int $iterCount = 0;
    public function __construct(private int $n) {}
    public function getIterator(): Generator {
        for ($i = 0; $i < $this->n; $i++) {
            $this->iterCount++;
            yield $i;
        }
    }
}

$c = new CounterAggregate(3);
foreach ($c as $v) ;
echo $c->iterCount, "\n";

$arr1 = new ArrayIterator([1, 2, 3]);
$arr2 = new ArrayIterator([4, 5, 6]);

$append = new AppendIterator;
$append->append($arr1);
$append->append($arr2);
$result = [];
foreach ($append as $v) $result[] = $v;
print_r($result);

print_r(range(0xff, 0xff + 3));

$mt = new MultipleIterator;
$mt->attachIterator(new ArrayIterator([1, 2, 3]));
$mt->attachIterator(new ArrayIterator(["a", "b", "c"]));
$result = [];
foreach ($mt as $pair) $result[] = implode("/", $pair);
print_r($result);
