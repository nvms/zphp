<?php
// covers: closures capture by reference, Closure::bind, Closure::bindTo,
//   Closure::fromCallable, arrow functions, first-class callable syntax,
//   recursive closures, closures as method args (array_map, array_filter,
//   usort), higher-order functions, static closures, array_reduce,
//   array_walk, variable function calls, is_callable, closure default
//   params, named arguments in closure calls

// --- capture by reference ---
echo "=== Capture by Reference ===\n";
$counter = 0;
$increment = function() use (&$counter) {
    $counter++;
};
$increment();
$increment();
$increment();
echo "counter: $counter\n";

$values = [];
$push = function($v) use (&$values) {
    $values[] = $v;
};
$push("a");
$push("b");
$push("c");
echo "values: " . implode(", ", $values) . "\n";

// --- Closure::bind and Closure::bindTo ---
echo "\n=== Closure::bind and bindTo ===\n";

class Wallet {
    private int $balance;
    public function __construct(int $balance) {
        $this->balance = $balance;
    }
}

$getBalance = function() {
    return $this->balance;
};

$setBalance = function(int $amount) {
    $this->balance = $amount;
};

$w1 = new Wallet(100);
$w2 = new Wallet(250);

$bound1 = Closure::bind($getBalance, $w1, Wallet::class);
$bound2 = $getBalance->bindTo($w2, Wallet::class);
echo "w1 balance: " . $bound1() . "\n";
echo "w2 balance: " . $bound2() . "\n";

$setter = Closure::bind($setBalance, $w1, Wallet::class);
$setter(500);
echo "w1 after set: " . $bound1() . "\n";

// --- Closure::fromCallable ---
echo "\n=== Closure::fromCallable ===\n";

function triple(int $n): int {
    return $n * 3;
}

$fn = Closure::fromCallable('triple');
echo "triple(7): " . $fn(7) . "\n";

class MathHelper {
    public static function square(int $n): int {
        return $n * $n;
    }

    public function cube(int $n): int {
        return $n * $n * $n;
    }
}

$sq = Closure::fromCallable([MathHelper::class, 'square']);
echo "square(5): " . $sq(5) . "\n";

$helper = new MathHelper();
$cu = Closure::fromCallable([$helper, 'cube']);
echo "cube(3): " . $cu(3) . "\n";

// --- arrow functions ---
echo "\n=== Arrow Functions ===\n";

$double = fn($x) => $x * 2;
echo "double(8): " . $double(8) . "\n";

$base = 10;
$addBase = fn($x) => $x + $base;
echo "addBase(5): " . $addBase(5) . "\n";

$compose = fn($f, $g) => fn($x) => $f($g($x));
$addOne = fn($x) => $x + 1;
$timesThree = fn($x) => $x * 3;
$addOneThenTriple = $compose($timesThree, $addOne);
echo "compose(triple, addOne)(4): " . $addOneThenTriple(4) . "\n";

// --- first-class callable syntax ---
echo "\n=== First-Class Callable Syntax ===\n";

$strlen = strlen(...);
echo "strlen('hello'): " . $strlen('hello') . "\n";

$arr = [3, 1, 4, 1, 5, 9];
$sorted = $arr;
sort($sorted);
echo "sorted: " . implode(", ", $sorted) . "\n";

class Formatter {
    public function upper(string $s): string {
        return strtoupper($s);
    }

    public static function lower(string $s): string {
        return strtolower($s);
    }
}

$fmt = new Formatter();
$upperFn = $fmt->upper(...);
echo "upper('hello'): " . $upperFn('hello') . "\n";

$lowerFn = Formatter::lower(...);
echo "lower('WORLD'): " . $lowerFn('WORLD') . "\n";

// --- recursive closures ---
echo "\n=== Recursive Closures ===\n";

$factorial = null;
$factorial = function(int $n) use (&$factorial): int {
    if ($n <= 1) return 1;
    return $n * $factorial($n - 1);
};
echo "factorial(6): " . $factorial(6) . "\n";

$fib = null;
$fib = function(int $n) use (&$fib): int {
    if ($n <= 1) return $n;
    return $fib($n - 1) + $fib($n - 2);
};
echo "fib(10): " . $fib(10) . "\n";

// --- closures as method arguments ---
echo "\n=== Closures as Method Arguments ===\n";

$names = ["charlie", "alice", "bob", "dave"];
$uppered = array_map(function($name) {
    return strtoupper($name);
}, $names);
echo "mapped: " . implode(", ", $uppered) . "\n";

$numbers = [1, 2, 3, 4, 5, 6, 7, 8];
$odds = array_values(array_filter($numbers, function($n) {
    return $n % 2 !== 0;
}));
echo "odds: " . implode(", ", $odds) . "\n";

$items = ["banana", "apple", "cherry", "date"];
usort($items, function($a, $b) {
    return strcmp($a, $b);
});
echo "sorted items: " . implode(", ", $items) . "\n";

// --- higher-order functions (closure returning closure) ---
echo "\n=== Higher-Order Functions ===\n";

function multiplier(int $factor): Closure {
    return function(int $n) use ($factor): int {
        return $n * $factor;
    };
}

$times5 = multiplier(5);
$times10 = multiplier(10);
echo "times5(3): " . $times5(3) . "\n";
echo "times10(3): " . $times10(3) . "\n";

function adder(int $amount): Closure {
    return fn(int $n) => $n + $amount;
}

$add100 = adder(100);
echo "add100(42): " . $add100(42) . "\n";

function pipeline(array $fns): Closure {
    return function($value) use ($fns) {
        foreach ($fns as $fn) {
            $value = $fn($value);
        }
        return $value;
    };
}

$transform = pipeline([
    fn($x) => $x * 2,
    fn($x) => $x + 10,
    fn($x) => $x * 3,
]);
echo "pipeline(5): " . $transform(5) . "\n";

// --- static closures ---
echo "\n=== Static Closures ===\n";

$static = static function(int $a, int $b): int {
    return $a + $b;
};
echo "static add(3, 4): " . $static(3, 4) . "\n";

$staticArrow = static fn(int $x) => $x * $x;
echo "static square(9): " . $staticArrow(9) . "\n";

// --- array_reduce and array_walk ---
echo "\n=== array_reduce and array_walk ===\n";

$nums = [1, 2, 3, 4, 5];
$product = array_reduce($nums, function($carry, $item) {
    return $carry * $item;
}, 1);
echo "product: $product\n";

$longest = array_reduce(["hi", "hello", "hey", "howdy"], function($carry, $item) {
    return strlen($item) > strlen($carry) ? $item : $carry;
}, "");
echo "longest: $longest\n";

$prices = ["apple" => 1.20, "banana" => 0.50, "cherry" => 2.00];
array_walk($prices, function(&$price, $name) {
    $price = round($price * 1.10, 2);
});
echo "taxed prices: ";
$parts = [];
foreach ($prices as $name => $price) {
    $parts[] = "$name=" . number_format($price, 2);
}
echo implode(", ", $parts) . "\n";

// --- variable function calls ---
echo "\n=== Variable Function Calls ===\n";

$fn = 'strlen';
echo "strlen('hello'): " . $fn('hello') . "\n";

$fn = 'strtoupper';
echo "upper('test'): " . $fn('test') . "\n";

$fn = 'array_sum';
echo "sum([1,2,3]): " . $fn([1, 2, 3]) . "\n";

// --- is_callable checks ---
echo "\n=== is_callable Checks ===\n";

echo "closure: " . (is_callable(function() {}) ? "yes" : "no") . "\n";
echo "arrow fn: " . (is_callable(fn() => 1) ? "yes" : "no") . "\n";
echo "string strlen: " . (is_callable('strlen') ? "yes" : "no") . "\n";
echo "string fake: " . (is_callable('not_a_real_function_xyz') ? "yes" : "no") . "\n";
echo "array static: " . (is_callable([MathHelper::class, 'square']) ? "yes" : "no") . "\n";
echo "array instance: " . (is_callable([$helper, 'cube']) ? "yes" : "no") . "\n";
echo "null: " . (is_callable(null) ? "yes" : "no") . "\n";
echo "int: " . (is_callable(42) ? "yes" : "no") . "\n";

// --- closures with default parameter values ---
echo "\n=== Closure Default Params ===\n";

$greet = function(string $name, string $greeting = "Hello") {
    return "$greeting, $name!";
};
echo $greet("Alice") . "\n";
echo $greet("Bob", "Hey") . "\n";

$repeat = fn(string $s, int $times = 3) => str_repeat($s, $times);
echo $repeat("ab") . "\n";
echo $repeat("xy", 2) . "\n";

// --- named arguments in closure calls ---
echo "\n=== Named Arguments in Closures ===\n";

$create = function(string $name, int $age, string $city = "unknown"): string {
    return "$name, age $age, from $city";
};
echo $create(name: "Alice", age: 30) . "\n";
echo $create("Bob", 25, "Paris") . "\n";

$calc = fn(int $a, int $b, string $op = "add") => match($op) {
    "add" => $a + $b,
    "mul" => $a * $b,
    default => 0,
};
echo "calc add: " . $calc(a: 3, b: 4) . "\n";
echo "calc mul: " . $calc(b: 5, a: 6, op: "mul") . "\n";
