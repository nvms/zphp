<?php
echo var_export(3.14, true), "\n";
echo var_export(0.1 + 0.2, true), "\n";
echo var_export(1.0, true), "\n";
echo var_export(0.0, true), "\n";
echo var_export(-0.0, true), "\n";
echo var_export(1e10, true), "\n";
echo var_export(1.5e-5, true), "\n";

echo var_export(NAN, true), "\n";
echo var_export(INF, true), "\n";
echo var_export(-INF, true), "\n";
echo var_export(PHP_FLOAT_EPSILON, true), "\n";

echo var_export("hello", true), "\n";
echo var_export("with 'quote'", true), "\n";
echo var_export("with \\backslash", true), "\n";
echo var_export("with \"double\"", true), "\n";
echo var_export("", true), "\n";
echo var_export("\n\t\r", true), "\n";

echo var_export(0, true), "\n";
echo var_export(-1, true), "\n";
echo var_export(PHP_INT_MAX, true), "\n";
echo var_export(PHP_INT_MIN, true), "\n";

echo var_export(true, true), "\n";
echo var_export(false, true), "\n";
echo var_export(null, true), "\n";

echo var_export([], true), "\n";
echo var_export([1, 2, 3], true), "\n";

echo var_export(["a" => 1], true), "\n";
echo var_export(["a" => 1, "b" => 2], true), "\n";
echo var_export([1, "two", 3.0, true, false, null], true), "\n";

$nested = [
    "users" => [
        "alice" => ["age" => 30],
        "bob" => ["age" => 25],
    ],
    "tags" => [1, 2, 3],
];
echo var_export($nested, true), "\n";

echo var_export([
    "key with spaces" => 1,
    "key'with'quotes" => 2,
    "key\\with\\backslash" => 3,
    "" => "empty",
], true), "\n";

echo var_export([0 => "first", 1 => "second", 2 => "third"], true), "\n";
echo var_export([10 => "ten", 5 => "five"], true), "\n";
echo var_export([-1 => "neg", 0 => "zero"], true), "\n";

class C {
    public int $a = 1;
    public string $b = "hello";
    public array $c = [10, 20];
    public ?object $d = null;
}
echo var_export(new C, true), "\n";

class WithSetState {
    public int $x = 0;
    public string $y = "";
    public static function __set_state(array $arr): self {
        $i = new self;
        $i->x = $arr["x"];
        $i->y = $arr["y"];
        return $i;
    }
}
$ws = new WithSetState;
$ws->x = 42;
$ws->y = "set";
echo var_export($ws, true), "\n";

echo var_export(new stdClass, true), "\n";

class Nested {
    public ?Nested $child = null;
    public string $name;
    public function __construct(string $n) { $this->name = $n; }
}
$root = new Nested("root");
$root->child = new Nested("middle");
$root->child->child = new Nested("leaf");
echo var_export($root, true), "\n";

$big = [];
for ($i = 0; $i < 5; $i++) $big[] = $i * 10;
echo var_export($big, true), "\n";

echo var_export([new C, new C], true), "\n";

echo var_export(["k" => 1.5, "j" => 2.5e10], true), "\n";

echo var_export(NAN), "\n";
echo "\n", var_export(INF), "\n";

$mixed = [
    "f" => 0.1 + 0.2,
    "i" => PHP_INT_MAX,
    "s" => "with 'quote' and \"dq\"",
    "n" => null,
    "b" => true,
    "a" => [1, 2, "three"],
];
echo var_export($mixed, true), "\n";

class Tree {
    public string $name;
    public array $children;
    public function __construct(string $n, array $c = []) {
        $this->name = $n;
        $this->children = $c;
    }
}

$t = new Tree("root", [
    new Tree("a"),
    new Tree("b", [new Tree("b1")]),
]);
echo var_export($t, true), "\n";

ob_start();
var_export(["hello"]);
$out = ob_get_clean();
echo strlen($out) > 0 ? "echo-ok" : "echo-bad", "\n";

echo var_export("php\n+8.4", true), "\n";

echo var_export(M_PI, true), "\n";
echo var_export(M_E, true), "\n";
