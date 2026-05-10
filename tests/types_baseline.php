<?php
// nullable
function n(?int $x): ?string {
    return $x === null ? null : "v:$x";
}
echo n(5) ?? "null", "\n";
echo n(null) ?? "null", "\n";

// nullable + default
function nd(?int $x = null): string {
    return $x === null ? "n" : "v:$x";
}
echo nd(), "\n";
echo nd(0), "\n";
echo nd(7), "\n";

// union types
function u(int|string $v): string {
    return gettype($v) . ":" . $v;
}
echo u(5), "\n";
echo u("hi"), "\n";

// scalar coercion at int|string boundary (architectural - zphp stricter than php loose mode)
try { u(null); echo "no\n"; } catch (\TypeError $e) { echo "te-null\n"; }

// nullable union
function un(int|string|null $v): string {
    return $v === null ? "n" : (gettype($v) . ":" . $v);
}
echo un(5), "\n";
echo un("x"), "\n";
echo un(null), "\n";

// intersection types
interface Countable2 {
    public function count2(): int;
}
interface Stringable2 {
    public function str2(): string;
}
class Both implements Countable2, Stringable2 {
    public function count2(): int { return 5; }
    public function str2(): string { return "five"; }
}
class CountOnly implements Countable2 {
    public function count2(): int { return 3; }
}
function inter(Countable2&Stringable2 $x): string {
    return $x->str2() . "/" . $x->count2();
}
echo inter(new Both), "\n";

try { inter(new CountOnly); echo "no\n"; } catch (\TypeError $e) { echo "inter-te\n"; }

// never type
function fail(): never {
    throw new RuntimeException("nope");
}
try { fail(); echo "no\n"; } catch (\RuntimeException $e) { echo "rt:", $e->getMessage(), "\n"; }

// void return
function v(): void {
    // no return
}
$r = v();
var_dump($r); // null

// void function returning value (architectural - eval not implemented)

// mixed accepts anything
function m(mixed $x): string {
    return gettype($x);
}
echo m(1), " ", m("a"), " ", m([]), " ", m(null), " ", m(new stdClass), " ", m(true), " ", m(1.5), "\n";

// self return type
class Builder {
    private array $items = [];
    public function add(string $s): self {
        $this->items[] = $s;
        return $this;
    }
    public function get(): array { return $this->items; }
}

$r = (new Builder)->add("a")->add("b")->add("c")->get();
print_r($r);

// static return type (LSB)
class A {
    public static function make(): static {
        return new static;
    }
    public string $name = "A";
}
class B extends A {
    public string $name = "B";
}
echo A::make()->name, " ", B::make()->name, "\n";

// self vs static covariance
class Parent1 {
    public function fluent(): self {
        return $this;
    }
}
class Child1 extends Parent1 {
    public string $extra = "extra";
}
$c = new Child1;
echo $c->fluent()->extra, "\n"; // self returns same instance, properties accessible

// array typed param
function takesArr(array $a): int { return count($a); }
echo takesArr([1, 2, 3]), "\n";

// callable typed
function callIt(callable $c, int $x): mixed {
    return $c($x);
}
echo callIt(fn($n) => $n * 2, 5), "\n";

// string|callable union
function maybe_callable(string|callable $f): string {
    if (is_callable($f)) return "called:" . $f("hello");
    return "string:$f";
}
echo maybe_callable("strtoupper"), "\n"; // both - PHP picks callable interpretation
echo maybe_callable(fn($s) => "[$s]"), "\n";

// scalar coercion at int param (architectural - zphp stricter than PHP loose mode)
function takeInt(int $x): int { return $x; }
echo takeInt(5), "\n";
try { takeInt([1, 2]); echo "no\n"; } catch (\TypeError $e) { echo "arr-te\n"; }

// iterable
function iter(iterable $i): array {
    $out = [];
    foreach ($i as $v) $out[] = $v;
    return $out;
}
print_r(iter([1, 2, 3]));
print_r(iter(new ArrayIterator(["a", "b"])));

// object type
function obj(object $o): string {
    return get_class($o);
}
echo obj(new stdClass), " ", obj(new Builder), "\n";

// false type (PHP 8.0+)
function f(): false {
    return false;
}
var_dump(f());

// true type (PHP 8.2+)
function t(): true {
    return true;
}
var_dump(t());

// type juggling: string and int comparison
var_dump("123" == 123);
var_dump("abc" == 0);
var_dump("0" == false);
var_dump([] == false);
var_dump(null == false);

// strict
var_dump("123" === 123);
var_dump("abc" === 0);
