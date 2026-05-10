<?php
$arr = [1, [2, [3, [4, [5]]]]];
array_walk_recursive($arr, function (&$v) { $v *= 10; });
print_r($arr);

$arr = ["a" => 1, "b" => ["c" => 2, "d" => ["e" => 3]]];
$collected = [];
array_walk_recursive($arr, function ($v, $k) use (&$collected) {
    $collected[] = "$k=$v";
});
print_r($collected);

$arr = [1, 2, 3];
array_walk_recursive($arr, function (&$v, $k, $factor) { $v *= $factor; }, 100);
print_r($arr);

$arr = [
    "user" => ["name" => "alice", "age" => 30],
    "tags" => ["admin", "active"],
];
array_walk_recursive($arr, function (&$v) {
    if (is_string($v)) $v = strtoupper($v);
});
print_r($arr);

class Node {
    public function __construct(public int $value, public array $children = []) {}
}

$tree = new Node(1, [
    new Node(2),
    new Node(3, [new Node(4), new Node(5)]),
]);

function modifyTree(Node $n, callable $fn): void {
    $fn($n);
    foreach ($n->children as $c) modifyTree($c, $fn);
}

modifyTree($tree, function (Node $n) {
    $n->value *= 10;
});

function dumpTree(Node $n, int $d = 0): void {
    echo str_repeat("  ", $d), $n->value, "\n";
    foreach ($n->children as $c) dumpTree($c, $d + 1);
}
dumpTree($tree);

function deepMap(array $a, callable $f): array {
    $out = [];
    foreach ($a as $k => $v) {
        $out[$k] = is_array($v) ? deepMap($v, $f) : $f($v);
    }
    return $out;
}
print_r(deepMap([1, [2, 3, [4, 5]], 6], fn($x) => $x * 2));

$nested = [
    "a" => 1,
    "b" => ["c" => 2, "d" => ["e" => 3, "f" => 4]],
    "g" => 5,
];
print_r(deepMap($nested, fn($x) => $x + 100));

function deepFilter(array $a, callable $pred): array {
    $out = [];
    foreach ($a as $k => $v) {
        if (is_array($v)) {
            $sub = deepFilter($v, $pred);
            if (!empty($sub)) $out[$k] = $sub;
        } elseif ($pred($v)) {
            $out[$k] = $v;
        }
    }
    return $out;
}
print_r(deepFilter([1, 2, [3, 4, [5, 6]], 7, 8], fn($x) => $x % 2 === 0));

function flatten(array $a): array {
    $out = [];
    array_walk_recursive($a, function ($v) use (&$out) {
        $out[] = $v;
    });
    return $out;
}
print_r(flatten([1, [2, [3, [4, [5]]]]]));

function objWalk(object $obj, callable $fn): void {
    foreach (get_object_vars($obj) as $k => $v) {
        $fn($obj, $k, $v);
        if (is_object($v)) objWalk($v, $fn);
    }
}

class Cfg {
    public int $val;
    public ?Cfg $next;
    public function __construct(int $v, ?Cfg $n = null) {
        $this->val = $v;
        $this->next = $n;
    }
}

$c = new Cfg(1, new Cfg(2, new Cfg(3)));
$values = [];
objWalk($c, function ($obj, $k, $v) use (&$values) {
    if ($k === "val") $values[] = $v;
});
print_r($values);

function deepCount(array $a): int {
    $count = 0;
    array_walk_recursive($a, function () use (&$count) { $count++; });
    return $count;
}
echo deepCount([1, [2, 3, [4, [5, 6, 7]]]]), "\n";

// nested arrays of associations
$dataset = [
    "users" => [
        ["name" => "alice", "tags" => ["admin", "active"]],
        ["name" => "bob", "tags" => ["guest"]],
    ],
];

$leaves = [];
array_walk_recursive($dataset, function ($v) use (&$leaves) {
    $leaves[] = $v;
});
print_r($leaves);

$copy = $dataset;
array_walk_recursive($copy, function (&$v) {
    if (is_string($v)) $v = "[$v]";
});
print_r($copy);
