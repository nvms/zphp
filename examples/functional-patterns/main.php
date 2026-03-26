<?php
// covers: closures with use/use(&$ref), first-class callables, array_map,
//   array_filter, array_reduce, usort, array_walk, call_user_func,
//   call_user_func_array, compact, extract, named arguments,
//   (int)/(string)/(float) casts in closures, arrow functions (fn =>),
//   recursive closures, closure as return value, closure composition

// --- higher-order functions ---

echo "=== Higher-Order Functions ===\n";

function pipe($value, ...$fns) {
    foreach ($fns as $fn) {
        $value = $fn($value);
    }
    return $value;
}

$result = pipe(
    "  Hello, World!  ",
    trim(...),
    strtolower(...),
    function($s) { return str_replace(' ', '-', $s); },
    function($s) { return preg_replace('/[^a-z0-9-]/', '', $s); }
);
echo "piped: $result\n";

// --- closure factories ---

echo "\n=== Closure Factories ===\n";

function multiplier($factor) {
    return function($x) use ($factor) {
        return $x * $factor;
    };
}

$double = multiplier(2);
$triple = multiplier(3);
echo "double(5): " . $double(5) . "\n";
echo "triple(5): " . $triple(5) . "\n";

$mapped = array_map($double, [1, 2, 3, 4, 5]);
echo "doubled: " . implode(', ', $mapped) . "\n";

// --- accumulator with ref captures ---

echo "\n=== Ref Capture Accumulator ===\n";

function makeCounter() {
    $count = 0;
    return [
        'increment' => function() use (&$count) { $count++; },
        'get' => function() use (&$count) { return $count; },
        'reset' => function() use (&$count) { $count = 0; },
    ];
}

$counter = makeCounter();
$counter['increment']();
$counter['increment']();
$counter['increment']();
echo "count: " . $counter['get']() . "\n";
$counter['reset']();
echo "after reset: " . $counter['get']() . "\n";

// --- map/filter/reduce pipeline ---

echo "\n=== Pipeline ===\n";

$orders = [
    ['item' => 'Widget', 'price' => 25.00, 'qty' => 3],
    ['item' => 'Gadget', 'price' => 75.00, 'qty' => 1],
    ['item' => 'Cable', 'price' => 5.00, 'qty' => 10],
    ['item' => 'Screen', 'price' => 200.00, 'qty' => 2],
    ['item' => 'Mouse', 'price' => 15.00, 'qty' => 5],
];

$totals = array_map(function($o) {
    return ['item' => $o['item'], 'total' => $o['price'] * $o['qty']];
}, $orders);

$expensive = array_filter($totals, function($o) {
    return $o['total'] > 50;
});

usort($expensive, function($a, $b) {
    return $b['total'] - $a['total'];
});

foreach ($expensive as $o) {
    echo "  " . str_pad($o['item'], 10) . '$' . number_format($o['total'], 2) . "\n";
}

$grand = array_reduce($totals, function($carry, $o) {
    return $carry + $o['total'];
}, 0);
echo "grand total: \$" . number_format($grand, 2) . "\n";

// --- compact/extract ---

echo "\n=== Compact/Extract ===\n";

$name = "Alice";
$age = 30;
$city = "Portland";

$data = compact('name', 'age', 'city');
echo "compact: " . implode(', ', array_map(function($k, $v) {
    return "$k=$v";
}, array_keys($data), array_values($data))) . "\n";

$other = ['color' => 'blue', 'food' => 'pizza'];
extract($other);
echo "extracted: color=$color, food=$food\n";

// --- call_user_func ---

echo "\n=== Call User Func ===\n";

function greet($name, $greeting = "Hello") {
    return "$greeting, $name!";
}

echo call_user_func('greet', 'Bob') . "\n";
echo call_user_func_array('greet', ['Charlie', 'Hi']) . "\n";

class Formatter {
    public static function upper($s) { return strtoupper($s); }
    public function lower($s) { return strtolower($s); }
}

echo call_user_func(['Formatter', 'upper'], 'hello') . "\n";
$fmt = new Formatter();
echo call_user_func([$fmt, 'lower'], 'WORLD') . "\n";

// --- recursive closure ---

echo "\n=== Recursive Closure ===\n";

$fibonacci = function($n) use (&$fibonacci) {
    if ($n <= 1) return $n;
    return $fibonacci($n - 1) + $fibonacci($n - 2);
};

$fibs = [];
for ($i = 0; $i < 10; $i++) {
    $fibs[] = $fibonacci($i);
}
echo "fibonacci: " . implode(', ', $fibs) . "\n";

// --- array_walk with ref ---

echo "\n=== Array Walk ===\n";

$prices = ['apple' => 1.50, 'banana' => 0.75, 'cherry' => 3.00];
array_walk($prices, function(&$price, $key) {
    $price = round($price * 1.1, 2);
});
foreach ($prices as $item => $price) {
    echo "  $item: \$" . number_format($price, 2) . "\n";
}

// --- type casts in closures ---

echo "\n=== Casts in Closures ===\n";

$values = ["42", "3.14", "true", "0"];
$ints = array_map(function($v) { return (int)$v; }, $values);
echo "ints: " . implode(', ', $ints) . "\n";

$floats = array_map(function($v) { return (float)$v; }, $values);
echo "floats: " . implode(', ', $floats) . "\n";

$strings = array_map(function($v) { return (string)((int)$v * 2); }, $values);
echo "doubled strings: " . implode(', ', $strings) . "\n";

// --- named arguments ---

echo "\n=== Named Arguments ===\n";

function createTag($tag, $content, $class = '', $id = '') {
    $attrs = '';
    if ($class !== '') $attrs .= " class=\"$class\"";
    if ($id !== '') $attrs .= " id=\"$id\"";
    return "<$tag$attrs>$content</$tag>";
}

echo createTag('div', 'Hello') . "\n";
echo createTag('p', 'World', class: 'highlight') . "\n";
echo createTag('span', 'Test', id: 'main', class: 'bold') . "\n";

// --- memoize pattern ---

echo "\n=== Memoize ===\n";

function memoize($fn) {
    $cache = [];
    return function($key) use (&$cache, $fn) {
        $skey = (string)$key;
        if (!array_key_exists($skey, $cache)) {
            $cache[$skey] = $fn($key);
        }
        return $cache[$skey];
    };
}

$expensive = memoize(function($n) {
    return $n * $n + 1;
});

echo "first: " . $expensive(5) . "\n";
echo "cached: " . $expensive(5) . "\n";
echo "new: " . $expensive(10) . "\n";

echo "\nDone.\n";
