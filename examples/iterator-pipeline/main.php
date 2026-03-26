<?php
// covers: generators (yield, yield from, send, return, key=>value yield),
//   generator methods (current, key, valid, next, getReturn), Fiber (start,
//   resume, suspend, getReturn, isTerminated), iterator chaining, generator
//   delegation, generator exception handling, closures as generator factories,
//   foreach on generators, generator state lifecycle

// --- fiber basics ---

echo "=== Fiber Basics ===\n";

$fiber = new Fiber(function(): string {
    $x = Fiber::suspend('first');
    $y = Fiber::suspend('second');
    return "got $x and $y";
});

$v1 = $fiber->start();
echo "suspend 1: $v1\n";
$v2 = $fiber->resume('hello');
echo "suspend 2: $v2\n";
$fiber->resume('world');
echo "return: " . $fiber->getReturn() . "\n";
echo "terminated: " . ($fiber->isTerminated() ? 'yes' : 'no') . "\n";

// --- fiber as coroutine ---

echo "\n=== Fiber Coroutine ===\n";

function make_counter(int $start): Fiber {
    return new Fiber(function() use ($start): void {
        $n = $start;
        while (true) {
            $cmd = Fiber::suspend($n);
            if ($cmd === 'inc') {
                $n++;
            } else if ($cmd === 'dec') {
                $n--;
            } else if ($cmd === 'stop') {
                return;
            }
        }
    });
}

$counter = make_counter(10);
echo "start: " . $counter->start() . "\n";
echo "inc: " . $counter->resume('inc') . "\n";
echo "inc: " . $counter->resume('inc') . "\n";
echo "dec: " . $counter->resume('dec') . "\n";
$counter->resume('stop');
echo "terminated: " . ($counter->isTerminated() ? 'yes' : 'no') . "\n";

// --- multiple fibers interleaved ---

echo "\n=== Interleaved Fibers ===\n";

function make_worker(string $name, int $steps): Fiber {
    return new Fiber(function() use ($name, $steps): string {
        for ($i = 1; $i <= $steps; $i++) {
            Fiber::suspend("$name step $i");
        }
        return "$name done";
    });
}

$workers = [
    make_worker('A', 3),
    make_worker('B', 2),
    make_worker('C', 3),
];

$log = [];
foreach ($workers as $w) {
    $log[] = $w->start();
}

$active = true;
while ($active) {
    $active = false;
    foreach ($workers as $w) {
        if (!$w->isTerminated()) {
            $val = $w->resume();
            if ($val !== null) {
                $log[] = $val;
            }
            if (!$w->isTerminated()) {
                $active = true;
            }
        }
    }
}

foreach ($workers as $w) {
    $log[] = $w->getReturn();
}

foreach ($log as $entry) {
    echo "$entry\n";
}

// --- basic generator pipeline ---

echo "\n=== Generator Pipeline ===\n";

function range_gen(int $start, int $end): Generator {
    for ($i = $start; $i <= $end; $i++) {
        yield $i;
    }
}

function filter_gen(Generator $source, callable $pred): Generator {
    foreach ($source as $val) {
        if ($pred($val)) {
            yield $val;
        }
    }
}

function map_gen(Generator $source, callable $fn): Generator {
    foreach ($source as $val) {
        yield $fn($val);
    }
}

function take_gen(Generator $source, int $n): Generator {
    $count = 0;
    foreach ($source as $val) {
        if ($count >= $n) break;
        yield $val;
        $count++;
    }
}

$nums = range_gen(1, 20);
$evens = filter_gen($nums, function($n) { return $n % 2 === 0; });
$doubled = map_gen($evens, function($n) { return $n * 2; });
$first5 = take_gen($doubled, 5);

$results = [];
foreach ($first5 as $val) {
    $results[] = $val;
}
echo "pipeline: " . implode(', ', $results) . "\n";

// --- key-value yield ---

echo "\n=== Key-Value Yield ===\n";

function indexed_items(): Generator {
    yield 'alpha' => 100;
    yield 'beta' => 200;
    yield 'gamma' => 300;
}

foreach (indexed_items() as $key => $val) {
    echo "$key: $val\n";
}

// --- generator with return value ---

echo "\n=== Generator Return ===\n";

function sum_gen(array $nums): Generator {
    $total = 0;
    foreach ($nums as $n) {
        $total += $n;
        yield $total;
    }
    return $total;
}

$gen = sum_gen([10, 20, 30, 40]);
$running = [];
foreach ($gen as $partial) {
    $running[] = $partial;
}
echo "running sums: " . implode(', ', $running) . "\n";
echo "final return: " . $gen->getReturn() . "\n";

// --- generator send ---

echo "\n=== Generator Send ===\n";

function accumulator(): Generator {
    $total = 0;
    while (true) {
        $val = yield $total;
        if ($val === null) break;
        $total += $val;
    }
    return $total;
}

$acc = accumulator();
$acc->current();
$acc->send(5);
$acc->send(10);
$acc->send(15);
$result = $acc->send(null);
echo "accumulated: " . $acc->getReturn() . "\n";

// --- generator state methods ---

echo "\n=== Generator State ===\n";

function three_items(): Generator {
    yield 'first';
    yield 'second';
    yield 'third';
}

$gen = three_items();
echo "valid before start: " . ($gen->valid() ? 'yes' : 'no') . "\n";
echo "current: " . $gen->current() . "\n";
echo "key: " . $gen->key() . "\n";
$gen->next();
echo "after next - current: " . $gen->current() . "\n";
echo "after next - key: " . $gen->key() . "\n";
$gen->next();
$gen->next();
echo "exhausted valid: " . ($gen->valid() ? 'yes' : 'no') . "\n";

// --- generator factory closures ---

echo "\n=== Generator Factory ===\n";

function make_repeater(string $value, int $times): Closure {
    return function() use ($value, $times): Generator {
        for ($i = 0; $i < $times; $i++) {
            yield $value;
        }
    };
}

$factory = make_repeater('ping', 3);
$gen = $factory();
$items = [];
foreach ($gen as $item) {
    $items[] = $item;
}
echo "repeated: " . implode(', ', $items) . "\n";

// --- chained generator transforms ---

echo "\n=== Chained Transforms ===\n";

function chunk_gen(Generator $source, int $size): Generator {
    $chunk = [];
    foreach ($source as $val) {
        $chunk[] = $val;
        if (count($chunk) === $size) {
            yield $chunk;
            $chunk = [];
        }
    }
    if (count($chunk) > 0) {
        yield $chunk;
    }
}

function flatten_gen(Generator $source): Generator {
    foreach ($source as $arr) {
        foreach ($arr as $val) {
            yield $val;
        }
    }
}

$nums = range_gen(1, 10);
$chunks = chunk_gen($nums, 3);
$flat = flatten_gen($chunks);
$doubled = map_gen($flat, function($n) { return $n * 2; });

$results = [];
foreach ($doubled as $val) {
    $results[] = $val;
}
echo "chunk-flatten-double: " . implode(', ', $results) . "\n";

// --- generator with exception ---

echo "\n=== Generator Exception ===\n";

function safe_divide_gen(array $pairs): Generator {
    foreach ($pairs as $pair) {
        try {
            if ($pair[1] === 0) {
                throw new Exception("division by zero");
            }
            yield $pair[0] / $pair[1];
        } catch (Exception $e) {
            yield "ERR: " . $e->getMessage();
        }
    }
}

$pairs = [[10, 2], [15, 3], [7, 0], [20, 4]];
$results = [];
foreach (safe_divide_gen($pairs) as $r) {
    $results[] = is_string($r) ? $r : (string)$r;
}
echo implode(', ', $results) . "\n";

// --- yield from delegation ---

echo "\n=== Yield From ===\n";

function inner_gen(): Generator {
    yield 'a';
    yield 'b';
    return 'inner-done';
}

function outer_gen(): Generator {
    $result = yield from inner_gen();
    echo "inner returned: $result\n";
    yield 'c';
    yield 'd';
}

$items = [];
foreach (outer_gen() as $val) {
    $items[] = $val;
}
echo "all items: " . implode(', ', $items) . "\n";

// --- nested yield from ---

echo "\n=== Nested Yield From ===\n";

function leaf(): Generator {
    yield 1;
    yield 2;
    return 'leaf-done';
}

function middle(): Generator {
    yield 0;
    $r = yield from leaf();
    yield 3;
    return "middle($r)";
}

function top(): Generator {
    $r = yield from middle();
    yield 4;
    return "top($r)";
}

$vals = [];
$gen = top();
foreach ($gen as $v) {
    $vals[] = $v;
}
echo "values: " . implode(', ', $vals) . "\n";
echo "top return: " . $gen->getReturn() . "\n";

// --- generator as data source ---

echo "\n=== Generator Data Source ===\n";

function csv_rows(): Generator {
    $data = [
        ['Alice', 30, 'Engineering'],
        ['Bob', 25, 'Marketing'],
        ['Carol', 35, 'Engineering'],
        ['Dave', 28, 'Marketing'],
        ['Eve', 32, 'Engineering'],
    ];
    foreach ($data as $row) {
        yield ['name' => $row[0], 'age' => $row[1], 'dept' => $row[2]];
    }
}

function where(Generator $source, string $field, $value): Generator {
    foreach ($source as $row) {
        if ($row[$field] === $value) {
            yield $row;
        }
    }
}

function select(Generator $source, string $field): Generator {
    foreach ($source as $row) {
        yield $row[$field];
    }
}

$names = select(where(csv_rows(), 'dept', 'Engineering'), 'name');
$eng = [];
foreach ($names as $name) {
    $eng[] = $name;
}
echo "engineering: " . implode(', ', $eng) . "\n";

// --- fiber with generator ---

echo "\n=== Fiber With Generator ===\n";

$fiber = new Fiber(function(): string {
    $gen = range_gen(1, 5);
    $sum = 0;
    foreach ($gen as $val) {
        $sum += $val;
        if ($val === 3) {
            Fiber::suspend("partial sum: $sum");
        }
    }
    return "total: $sum";
});

echo $fiber->start() . "\n";
$fiber->resume();
echo $fiber->getReturn() . "\n";

echo "\nDone.\n";
