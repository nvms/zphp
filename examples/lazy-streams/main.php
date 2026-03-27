<?php
// covers: generators, yield, yield from, iterator_to_array, closures, array_sum, array_product, func_get_args, call_user_func, array_merge

// --- generators as lazy sequences ---

function naturals(int $start = 1): Generator {
    $n = $start;
    while (true) {
        yield $n++;
    }
}

function take(Generator $gen, int $n): array {
    $result = [];
    $count = 0;
    foreach ($gen as $value) {
        $result[] = $value;
        $count++;
        if ($count >= $n) break;
    }
    return $result;
}

echo "First 5 naturals: " . implode(', ', take(naturals(), 5)) . "\n";
echo "From 10: " . implode(', ', take(naturals(10), 5)) . "\n";

// --- fibonacci generator ---

function fibonacci(): Generator {
    $a = 0;
    $b = 1;
    while (true) {
        yield $a;
        $temp = $a + $b;
        $a = $b;
        $b = $temp;
    }
}

echo "Fibonacci: " . implode(', ', take(fibonacci(), 10)) . "\n";

// --- range generator ---

function rangeGen(int $start, int $end, int $step = 1): Generator {
    if ($step > 0) {
        for ($i = $start; $i <= $end; $i += $step) {
            yield $i;
        }
    } else {
        for ($i = $start; $i >= $end; $i += $step) {
            yield $i;
        }
    }
}

echo "Range(1,10,2): " . implode(', ', iterator_to_array(rangeGen(1, 10, 2), false)) . "\n";
echo "Range(10,1,-3): " . implode(', ', iterator_to_array(rangeGen(10, 1, -3), false)) . "\n";

// --- generator pipeline: map/filter/reduce ---

function genMap(Generator $gen, callable $fn): Generator {
    foreach ($gen as $value) {
        yield $fn($value);
    }
}

function genFilter(Generator $gen, callable $fn): Generator {
    foreach ($gen as $value) {
        if ($fn($value)) {
            yield $value;
        }
    }
}

function genReduce(Generator $gen, callable $fn, $initial) {
    $acc = $initial;
    foreach ($gen as $value) {
        $acc = $fn($acc, $value);
    }
    return $acc;
}

$evens = genFilter(naturals(), function($n) { return $n % 2 === 0; });
$squared = genMap($evens, function($n) { return $n * $n; });
$first5 = take($squared, 5);
echo "First 5 even squares: " . implode(', ', $first5) . "\n";

$sum = genReduce(rangeGen(1, 100), function($acc, $n) { return $acc + $n; }, 0);
echo "Sum 1..100: $sum\n";

// --- yield from (delegation) ---

function inner(): Generator {
    yield 'a';
    yield 'b';
    yield 'c';
}

function outer(): Generator {
    yield 'start';
    yield from inner();
    yield 'end';
}

echo "Delegated: " . implode(', ', iterator_to_array(outer(), false)) . "\n";

// --- chunked reading ---

function chunks(array $data, int $size): Generator {
    $len = count($data);
    for ($i = 0; $i < $len; $i += $size) {
        yield array_slice($data, $i, $size);
    }
}

echo "\nChunked processing:\n";
$data = range(1, 12);
foreach (chunks($data, 4) as $chunk) {
    echo "  batch: [" . implode(', ', $chunk) . "] sum=" . array_sum($chunk) . "\n";
}

// --- memoize with closures ---

function memoize(callable $fn): callable {
    $cache = [];
    return function() use ($fn, &$cache) {
        $args = func_get_args();
        $key = implode(':', array_map('strval', $args));
        if (!array_key_exists($key, $cache)) {
            $cache[$key] = call_user_func_array($fn, $args);
        }
        return $cache[$key];
    };
}

$factorial = memoize(function(int $n) use (&$factorial): int {
    if ($n <= 1) return 1;
    return $n * $factorial($n - 1);
});

echo "\nMemoized factorial:\n";
echo "  5! = " . $factorial(5) . "\n";
echo "  10! = " . $factorial(10) . "\n";

// --- pipe function ---

function pipe(string $value): string {
    $value = trim($value);
    $value = strtoupper($value);
    $value = str_replace(' ', '-', $value);
    return "[$value]";
}

$result = pipe("  Hello, World!  ");
echo "\nPipe: $result\n";

// --- generator with return value ---

function sumGenerator(array $items): Generator {
    $total = 0;
    foreach ($items as $item) {
        $total += $item;
        yield $total;
    }
}

$sums = [];
foreach (sumGenerator([10, 20, 30]) as $runningTotal) {
    $sums[] = $runningTotal;
}
echo "\nRunning sums: " . implode(', ', $sums) . "\n";

// --- counter with ref captures ---

function testCounter(): void {
    $count = 0;
    $inc = function() use (&$count) {
        $count++;
        return $count;
    };
    echo "\nCounter:\n";
    echo "  " . $inc() . "\n";
    echo "  " . $inc() . "\n";
    echo "  " . $inc() . "\n";
}

testCounter();
