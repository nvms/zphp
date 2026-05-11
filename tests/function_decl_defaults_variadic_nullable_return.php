<?php
function add(int $a, int $b = 10): int {
    return $a + $b;
}
echo add(5), "\n";
echo add(5, 7), "\n";
echo add(a: 1, b: 2), "\n";
echo add(b: 100, a: 1), "\n";

function greet(string $name = "world", string $prefix = "hello"): string {
    return "$prefix, $name";
}
echo greet(), "\n";
echo greet("alice"), "\n";
echo greet("alice", "hi"), "\n";
echo greet(prefix: "hey"), "\n";

function modify(int &$x, int $by = 1): void {
    $x += $by;
}
$v = 10;
modify($v);
echo $v, "\n";
modify($v, 5);
echo $v, "\n";

function variadic(int ...$nums): int {
    return array_sum($nums);
}
echo variadic(), "\n";
echo variadic(1, 2, 3), "\n";
echo variadic(...[10, 20, 30]), "\n";

function mixed_args(string $first, int ...$rest): string {
    return $first . ":" . implode(",", $rest);
}
echo mixed_args("a"), "\n";
echo mixed_args("b", 1, 2, 3), "\n";
try { mixed_args(first: "c", rest: [4, 5]); echo "no\n"; } catch (\TypeError $e) { echo "te\n"; }

function maybeNull(?string $s = null): string {
    return $s ?? "null";
}
echo maybeNull(), "\n";
echo maybeNull(null), "\n";
echo maybeNull("hello"), "\n";

function withDefaults(int $a, string $b = "x", float $c = 3.14, bool $d = true): string {
    return "$a/$b/$c/" . ($d ? "true" : "false");
}
echo withDefaults(1), "\n";
echo withDefaults(1, "y"), "\n";
echo withDefaults(1, "y", 1.5), "\n";
echo withDefaults(1, "y", 1.5, false), "\n";
echo withDefaults(1, c: 2.5), "\n";
echo withDefaults(1, d: false), "\n";

class Base {
    public function get(): Base { return $this; }
}

class Child extends Base {
    public function get(): Child { return $this; }
}

$c = new Child;
echo get_class($c->get()), "\n";

function takesNullable(?int $x): int {
    return $x ?? 0;
}
echo takesNullable(5), "\n";
echo takesNullable(null), "\n";

function strict(string $s): string { return $s; }
echo strict("hi"), "\n";

function unionType(int|string $x): string {
    return is_int($x) ? "int:$x" : "str:$x";
}
echo unionType(5), "\n";
echo unionType("hello"), "\n";

class MyIter implements Iterator, Countable {
    public function rewind(): void {}
    public function valid(): bool { return false; }
    public function current(): mixed { return null; }
    public function key(): mixed { return 0; }
    public function next(): void {}
    public function count(): int { return 42; }
}
echo (new MyIter)->count(), "\n";

function arrCb(array $arr, ?callable $cb = null): array {
    if ($cb === null) return $arr;
    return array_map($cb, $arr);
}
print_r(arrCb([1, 2, 3]));
print_r(arrCb([1, 2, 3], fn($x) => $x * 2));

function recursive(int $n): int {
    return $n <= 0 ? 0 : $n + recursive($n - 1);
}
echo recursive(5), "\n";
echo recursive(10), "\n";

function partial(string $prefix): callable {
    return fn(string $s) => $prefix . $s;
}
$pre = partial("[INFO] ");
echo $pre("hello"), "\n";

function nullableReturn(int $x): ?string {
    return $x > 0 ? "positive" : null;
}
echo nullableReturn(1) ?? "null", "\n";
echo nullableReturn(-1) ?? "null", "\n";

function arrayReturn(): array {
    return [1, 2, 3];
}
print_r(arrayReturn());

function voidFn(): void {
}
echo voidFn() ?? "void", "\n";

function mixedFn(mixed $x): mixed {
    return $x;
}
echo mixedFn(42), "\n";
echo mixedFn("hi"), "\n";

function trueFn(): true {
    return true;
}
echo trueFn() === true ? "y" : "n", "\n";

function falseFn(): false {
    return false;
}
echo falseFn() === false ? "y" : "n", "\n";

function neverFn(): never {
    throw new \RuntimeException("never");
}

try {
    neverFn();
    echo "no\n";
} catch (\RuntimeException $e) {
    echo "caught\n";
}

class StaticReturn {
    public static function make(): static {
        return new static;
    }
}
class ExtStaticReturn extends StaticReturn {}
echo get_class(ExtStaticReturn::make()), "\n";

function multiReturn(int $code): int|string {
    return $code >= 0 ? $code : "neg";
}
echo multiReturn(5), "\n";
echo multiReturn(-1), "\n";

function objArg(object $o): string {
    return get_class($o);
}
echo objArg(new stdClass), "\n";

function iterableArg(iterable $i): int {
    $count = 0;
    foreach ($i as $v) $count++;
    return $count;
}
echo iterableArg([1, 2, 3]), "\n";

function generatorIterable(): Generator {
    yield 1;
    yield 2;
    yield 3;
}
echo iterableArg(generatorIterable()), "\n";

class A {
    public function clone_(): self { return new self; }
    public function staticOne(): static { return new static; }
}

echo get_class((new A)->clone_()), "\n";
echo get_class((new A)->staticOne()), "\n";
