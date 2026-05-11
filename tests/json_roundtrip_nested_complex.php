<?php
class Point {
    public function __construct(public float $x, public float $y) {}
}

$p = new Point(3.0, 4.0);
$json = json_encode($p);
echo $json, "\n";

$decoded = json_decode($json, true);
print_r($decoded);

$decoded = json_decode($json);
echo $decoded->x, " ", $decoded->y, "\n";

$arr = [
    "name" => "alice",
    "scores" => [90, 85, 95],
    "address" => ["street" => "123 Main", "city" => "Anywhere"],
    "active" => true,
    "metadata" => null,
];

$json = json_encode($arr);
echo $json, "\n";

$back = json_decode($json, true);
print_r($back);

$nested = ["a" => ["b" => ["c" => ["d" => "deep"]]]];
$json = json_encode($nested);
$back = json_decode($json, true);
echo $back["a"]["b"]["c"]["d"], "\n";

class User implements JsonSerializable {
    public function __construct(public string $name, public int $age) {}
    public function jsonSerialize(): array {
        return ["name" => strtoupper($this->name), "age" => $this->age];
    }
}

echo json_encode(new User("alice", 30)), "\n";
echo json_encode([new User("a", 1), new User("b", 2)]), "\n";

class Tree {
    public ?Tree $left = null;
    public ?Tree $right = null;
    public function __construct(public int $val) {}
}

$root = new Tree(1);
$root->left = new Tree(2);
$root->right = new Tree(3);
$root->left->left = new Tree(4);

echo json_encode($root), "\n";

$decoded = json_decode(json_encode($root), true);
print_r($decoded);

$arr = [1, "two", 3.14, true, false, null];
echo json_encode($arr), "\n";

$assoc = ["a" => 1, "b" => "two", "c" => true];
echo json_encode($assoc), "\n";

echo json_encode([]), "\n";
echo json_encode([1]), "\n";
echo json_encode(["k" => "v"]), "\n";
echo json_encode([], JSON_FORCE_OBJECT), "\n";

$ints = [1, 2, 3];
$json = json_encode($ints);
$back = json_decode($json, true);
echo array_sum($back), "\n";

echo json_encode([
    "list" => [
        ["id" => 1, "name" => "a"],
        ["id" => 2, "name" => "b"],
    ],
]), "\n";

echo strlen(json_encode(array_fill(0, 100, "x"))), "\n";

$utf = "héllo 日本語";
echo json_encode($utf), "\n";
echo json_decode(json_encode($utf)), "\n";

$controls = "\t\n\r\\\"";
echo json_encode($controls), "\n";
echo json_decode(json_encode($controls)) === $controls ? "y" : "n", "\n";

$big = ["data" => array_fill(0, 50, "x")];
$json = json_encode($big);
$back = json_decode($json, true);
echo count($back["data"]) === 50 ? "y" : "n", "\n";
echo $back["data"][0] === "x" ? "y" : "n", "\n";

echo json_encode([
    "nested" => ["mixed" => [1, "two", 3.14, ["deep" => "value"]]],
]), "\n";

$mixed = [
    "tags" => (object)["x" => 1, "y" => 2],
    "items" => [(object)["a" => 1], (object)["a" => 2]],
];
echo json_encode($mixed), "\n";

$arr = [[1, 2], [3, 4], [5, 6]];
echo json_encode($arr), "\n";

class Stack {
    public array $items = [];
    public function push($x): void { $this->items[] = $x; }
}
$s = new Stack;
$s->push("a");
$s->push("b");
$s->push(["nested", 1]);
echo json_encode($s), "\n";

$arr1 = ["a" => ["b" => ["c" => 1]]];
$arr2 = ["a" => ["b" => ["d" => 2]]];
$merged = array_merge_recursive($arr1, $arr2);
echo json_encode($merged), "\n";

echo json_encode(["floats" => [0.1, 1.5, 2.75, -3.14]]), "\n";

echo json_encode([INF]) === false ? "n" : "y", "\n";
echo json_encode([NAN]) === false ? "n" : "y", "\n";

echo json_encode("simple"), "\n";
echo json_encode(42), "\n";
echo json_encode(3.14), "\n";
echo json_encode(true), "\n";
echo json_encode(false), "\n";
echo json_encode(null), "\n";

echo var_export(json_decode("null"), true), "\n";
echo var_export(json_decode("true"), true), "\n";
echo var_export(json_decode("123"), true), "\n";
echo var_export(json_decode('"str"'), true), "\n";
echo var_export(json_decode("[]"), true), "\n";
echo var_export(json_decode("[]", true), true), "\n";
echo var_export(json_decode("{}"), true), "\n";
echo var_export(json_decode("{}", true), true), "\n";

$round = ["k1" => 1, "k2" => "v", "k3" => [1, 2, 3], "k4" => null];
echo json_encode($round) === json_encode(json_decode(json_encode($round), true)) ? "rt" : "diff", "\n";
