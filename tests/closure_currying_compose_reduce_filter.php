<?php
$add = fn($a) => fn($b) => $a + $b;
echo $add(5)(3), "\n";
echo $add(10)(20), "\n";

$mul = fn($a, $b) => $a * $b;
$double = fn($x) => $mul($x, 2);
$triple = fn($x) => $mul($x, 3);
echo $double(5), " ", $triple(5), "\n";

$nums = [1, 2, 3, 4, 5];
$result = array_reduce(
    array_filter($nums, fn($n) => $n % 2 === 1),
    fn($acc, $n) => $acc + $n * $n,
    0
);
echo $result, "\n";

$result = array_reduce(
    array_map(fn($n) => $n * 2, $nums),
    fn($acc, $n) => $acc + $n,
    0
);
echo $result, "\n";

$compose = fn(callable $f, callable $g) => fn($x) => $f($g($x));
$inc = fn($x) => $x + 1;
$square = fn($x) => $x * $x;
$incThenSquare = $compose($square, $inc);
echo $incThenSquare(4), "\n";

$pipe = function (...$fns) {
    return fn($x) => array_reduce($fns, fn($acc, $f) => $f($acc), $x);
};
$transform = $pipe(
    fn($x) => $x + 10,
    fn($x) => $x * 2,
    fn($x) => $x - 5
);
echo $transform(3), "\n";

$curry3 = fn($a) => fn($b) => fn($c) => $a + $b + $c;
echo $curry3(1)(2)(3), "\n";

$partial = function ($fn, ...$args) {
    return fn(...$rest) => $fn(...$args, ...$rest);
};
$addAll = fn(...$ns) => array_sum($ns);
$add10 = $partial($addAll, 10);
echo $add10(20, 30), "\n";

$words = ["the", "quick", "brown", "fox"];
$longest = array_reduce(
    $words,
    fn($best, $w) => strlen($w) > strlen($best) ? $w : $best,
    ""
);
echo $longest, "\n";

$users = [
    ["name" => "alice", "age" => 30, "active" => true],
    ["name" => "bob", "age" => 25, "active" => false],
    ["name" => "carol", "age" => 40, "active" => true],
    ["name" => "dave", "age" => 35, "active" => true],
];

$activeAvgAge = array_reduce(
    array_filter($users, fn($u) => $u["active"]),
    fn($acc, $u) => ["sum" => $acc["sum"] + $u["age"], "count" => $acc["count"] + 1],
    ["sum" => 0, "count" => 0]
);
echo $activeAvgAge["sum"] / $activeAvgAge["count"], "\n";

$grouped = array_reduce(
    $users,
    function ($acc, $u) {
        $key = $u["active"] ? "active" : "inactive";
        $acc[$key][] = $u["name"];
        return $acc;
    },
    ["active" => [], "inactive" => []]
);
print_r($grouped);

$flatten = function (array $nested) {
    return array_reduce($nested, fn($flat, $part) => array_merge($flat, $part), []);
};
print_r($flatten([[1, 2], [3, 4], [5]]));

$count = fn(array $arr, callable $pred) => array_reduce(
    array_filter($arr, $pred),
    fn($c) => $c + 1,
    0
);
echo $count([1, 2, 3, 4, 5, 6], fn($n) => $n % 2 === 0), "\n";

$counter = function () {
    $n = 0;
    return function () use (&$n) { return ++$n; };
};
$c1 = $counter();
echo $c1(), " ", $c1(), " ", $c1(), "\n";

$multiplier = function ($factor) {
    return function ($x) use ($factor) { return $x * $factor; };
};
$x10 = $multiplier(10);
$x100 = $multiplier(100);
echo $x10(5), " ", $x100(5), "\n";

$memoize = function (callable $fn) {
    $cache = [];
    return function ($x) use ($fn, &$cache) {
        if (!isset($cache[$x])) $cache[$x] = $fn($x);
        return $cache[$x];
    };
};
$square = fn($x) => $x * $x;
$msq = $memoize($square);
echo $msq(5), " ", $msq(5), "\n";

$nums = [10, 20, 30, 40];
$sumDoubled = array_reduce(
    array_map(fn($n) => $n * 2, $nums),
    fn($a, $b) => $a + $b,
    0
);
echo $sumDoubled, "\n";

$flow = function ($input, ...$ops) {
    return array_reduce($ops, fn($acc, $op) => $op($acc), $input);
};
echo $flow(5,
    fn($x) => $x * 2,
    fn($x) => $x + 1,
    fn($x) => strval($x)
), "\n";

$products = array_reduce(
    [1, 2, 3, 4, 5],
    fn($acc, $n) => $acc * $n,
    1
);
echo $products, "\n";

$concat = array_reduce(
    ["a", "b", "c", "d"],
    fn($acc, $s) => $acc . $s,
    ""
);
echo $concat, "\n";

$values = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
$result = array_reduce(
    array_filter($values, fn($n) => $n > 3 && $n < 8),
    fn($acc, $n) => array_merge($acc, [$n * 10]),
    []
);
print_r($result);

$ops = [
    "double" => fn($x) => $x * 2,
    "negate" => fn($x) => -$x,
    "square" => fn($x) => $x * $x,
];
$applied = array_map(fn($op) => $op(5), $ops);
print_r($applied);

class Tagged {
    public function __construct(public string $tag, public int $value) {}
}

$items = [new Tagged("a", 10), new Tagged("b", 20), new Tagged("a", 30), new Tagged("c", 40)];
$byTag = array_reduce(
    $items,
    function ($acc, $t) {
        $acc[$t->tag] = ($acc[$t->tag] ?? 0) + $t->value;
        return $acc;
    },
    []
);
print_r($byTag);

$swap = fn(callable $f) => fn($a, $b) => $f($b, $a);
$sub = fn($a, $b) => $a - $b;
$rsub = $swap($sub);
echo $sub(10, 3), " ", $rsub(10, 3), "\n";

$identity = fn($x) => $x;
echo $identity(42), "\n";
echo $identity("hello"), "\n";

$const = fn($v) => fn() => $v;
$always7 = $const(7);
echo $always7(), " ", $always7(), "\n";
