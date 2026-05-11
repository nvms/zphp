<?php
$records = [
    ["id" => 1, "name" => "alice", "age" => 30],
    ["id" => 2, "name" => "bob", "age" => 25],
    ["id" => 3, "name" => "carol", "age" => 40],
];

print_r(array_column($records, "name"));
print_r(array_column($records, "age"));
print_r(array_column($records, "id"));

print_r(array_column($records, "name", "id"));
print_r(array_column($records, "age", "name"));
print_r(array_column($records, null, "id"));
print_r(array_column($records, null, "name"));

print_r(array_column($records, "missing"));
print_r(array_column($records, "name", "missing"));

print_r(array_column([], "name"));
print_r(array_column([], null, "id"));

$objects = [];
foreach ($records as $r) {
    $o = new stdClass;
    $o->id = $r["id"];
    $o->name = $r["name"];
    $o->age = $r["age"];
    $objects[] = $o;
}
print_r(array_column($objects, "name"));
print_r(array_column($objects, "name", "id"));
print_r(array_column($objects, null, "id"));

class User {
    public int $id;
    public string $name;
    public function __construct(int $i, string $n) { $this->id = $i; $this->name = $n; }
}
$users = [new User(1, "a"), new User(2, "b"), new User(3, "c")];
print_r(array_column($users, "name"));
print_r(array_column($users, "name", "id"));

$mixed = [
    ["k" => 1, "v" => "x"],
    ["k" => 2, "v" => "y"],
    ["k" => 1, "v" => "z"],
];
print_r(array_column($mixed, "v", "k"));

print_r(array_column($records, "name", null));

print_r(range(1, 5));
print_r(range(5, 1));
print_r(range(1, 10, 2));
print_r(range(0, 1, 0.25));
print_r(range(10, 1, 3));
print_r(range(-5, 5));
print_r(range(-2, 2, 0.5));

print_r(range("a", "e"));
print_r(range("a", "j", 2));
print_r(range("z", "x"));
print_r(range("A", "C"));

print_r(range(1, 1));
print_r(range("a", "a"));
print_r(range(0, 0));

print_r(range(1.5, 4.5));
print_r(range(1.5, 4.5, 1.0));

try {
    print_r(range(1, 5, 0));
    echo "no\n";
} catch (\ValueError $e) {
    echo "ve\n";
}

try {
    print_r(range(1, 5, -1));
    echo "no\n";
} catch (\ValueError $e) {
    echo "ve\n";
}

echo count(range(1, 100)), "\n";
echo count(range(1, 100, 2)), "\n";
echo count(range("a", "z")), "\n";

print_r(range(5, 5, 1));
print_r(range(0, 0.0001, 0.0001));

print_r(array_column([], null));
print_r(array_column([["x" => 1], ["x" => 2]], "x"));

$ints = [10, 20, 30, 40];
$keys = ["a", "b", "c", "d"];
print_r(array_combine($keys, $ints));

print_r(array_column([
    ["k" => "first", "v" => 1],
    ["k" => "second", "v" => 2],
], "v", "k"));

print_r(array_column([
    [1 => "a"],
    [1 => "b"],
    [1 => "c"],
], 1));

$nested = [
    ["meta" => ["id" => 1], "name" => "x"],
    ["meta" => ["id" => 2], "name" => "y"],
];
print_r(array_column($nested, "name"));
