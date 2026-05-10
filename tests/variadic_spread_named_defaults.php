<?php
function sum(...$nums): int {
    return array_sum($nums);
}
echo sum(), "\n";
echo sum(1), "\n";
echo sum(1, 2, 3), "\n";
echo sum(...[1, 2, 3, 4]), "\n";

function prefix(string $p, ...$items): string {
    return $p . implode(",", $items);
}
echo prefix(":"), "\n";
echo prefix(">", "a", "b", "c"), "\n";
echo prefix(">", ...["x", "y"]), "\n";

function combine(int $a, int $b, ...$rest): int {
    return $a + $b + array_sum($rest);
}
echo combine(1, 2), "\n";
echo combine(1, 2, 3), "\n";
echo combine(1, 2, ...[10, 20, 30]), "\n";

$args = [10, 20, 30];
echo combine(...$args), "\n";
echo combine(1, ...[2, 3]), "\n";
echo combine(1, 2, 3, ...[4, 5]), "\n";

function greet(string $name, int $age, string $city): string {
    return "$name/$age/$city";
}

echo greet(name: "alice", age: 30, city: "NYC"), "\n";
echo greet(city: "LA", age: 25, name: "bob"), "\n";
echo greet("charlie", city: "SF", age: 40), "\n";
echo greet(...["name" => "dave", "age" => 35, "city" => "Austin"]), "\n";
echo greet("eve", ...["city" => "Berlin", "age" => 28]), "\n";

function defaults(string $a, int $b = 10, string $c = "default"): string {
    return "$a/$b/$c";
}
echo defaults("x"), "\n";
echo defaults("x", 99), "\n";
echo defaults("x", 99, "z"), "\n";
echo defaults("x", c: "y"), "\n";
echo defaults("x", b: 50), "\n";
echo defaults(a: "x"), "\n";
echo defaults("x", ...["b" => 7]), "\n";
echo defaults("x", ...["c" => "z"]), "\n";

function take(int $a, int ...$rest): array {
    return [$a, $rest];
}
print_r(take(1));
print_r(take(1, 2));
print_r(take(1, 2, 3, 4));
print_r(take(1, ...[2, 3]));

function mixedTypes(int $i, float $f, string $s, ...$rest): string {
    return "$i/$f/$s/[" . implode(",", $rest) . "]";
}
echo mixedTypes(1, 2.5, "x"), "\n";
echo mixedTypes(1, 2.5, "x", "a", "b"), "\n";
echo mixedTypes(...[1, 2.5, "x", "extra"]), "\n";

function appliedSpread(): int {
    $args = [1, 2, 3];
    return sum(...$args);
}
echo appliedSpread(), "\n";

class Builder {
    public function build(string $name, ...$tags): string {
        return $name . "[" . implode(",", $tags) . "]";
    }
}
$b = new Builder;
echo $b->build("x"), "\n";
echo $b->build("y", "a", "b"), "\n";
echo $b->build("z", ...["c", "d", "e"]), "\n";

class StaticBuilder {
    public static function make(int $i, int ...$nums): int {
        return $i + array_sum($nums);
    }
}
echo StaticBuilder::make(10, 1, 2, 3), "\n";
echo StaticBuilder::make(10, ...[5, 6, 7]), "\n";

$f = fn(...$args) => count($args);
echo $f(), "\n";
echo $f(1, 2, 3, 4, 5), "\n";

$g = function (int $first, int ...$rest) {
    return $first - array_sum($rest);
};
echo $g(100, 10, 20, 30), "\n";
echo $g(100), "\n";

$args = [];
$args["name"] = "frank";
$args["age"] = 50;
$args["city"] = "Tokyo";
echo greet(...$args), "\n";

function nullableVar(?string $first = null, ...$rest): string {
    return ($first ?? "?") . ":" . count($rest);
}
echo nullableVar(), "\n";
echo nullableVar("a"), "\n";
echo nullableVar("a", "b", "c"), "\n";
echo nullableVar(null, 1, 2), "\n";

$nums = [1, 2, 3];
$more = [4, 5];
echo sum(...$nums, ...$more), "\n";
echo sum(0, ...$nums, ...$more), "\n";

function nameRequired(string $name): string { return "n:$name"; }
echo nameRequired(name: "alice"), "\n";

$arr = ["name" => "bob"];
echo nameRequired(...$arr), "\n";

function unpacksTraversable(array $a): int {
    return array_sum($a);
}
echo unpacksTraversable([1, 2, 3]), "\n";

function takesMixed(mixed ...$values): string {
    return implode("|", array_map(fn($v) => is_array($v) ? json_encode($v) : (string)$v, $values));
}
echo takesMixed(1, "a", [2, 3], 4.5, true), "\n";
