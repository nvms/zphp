<?php
function f(string $a, int $b = 10, int ...$rest): array { return [$a, $b, $rest]; }
print_r(f("a"));
print_r(f("b", 99));
print_r(f("c", 99, 1, 2, 3));

function greet(string $greeting = "Hello", string $name = "world"): string { return "$greeting, $name!"; }
echo greet(), "\n";
echo greet(name: "alice"), "\n";
echo greet(greeting: "Hi", name: "bob"), "\n";
echo greet("Howdy", name: "dave"), "\n";

class Calc {
    public function compute(int $a, int $b = 10, int $c = 100): int { return $a + $b + $c; }
}
$c = new Calc;
echo $c->compute(1), "\n";
echo $c->compute(a: 1, c: 5), "\n";
echo $c->compute(...["a" => 1, "b" => 2, "c" => 3]), "\n";

function with_pos_named(int $a, int $b, int $c = 100): int { return $a + $b + $c; }
echo with_pos_named(1, 2), "\n";
echo with_pos_named(1, 2, c: 7), "\n";
echo with_pos_named(a: 10, b: 20), "\n";

class Person {
    public function __construct(public string $name, public int $age, public ?string $email = null) {}
}
$p = new Person(name: "alice", age: 30);
echo $p->name, " ", $p->age, " ", $p->email ?? "null", "\n";
$p2 = new Person(age: 25, name: "bob", email: "b@e.com");
echo $p2->name, " ", $p2->age, " ", $p2->email, "\n";

class Format {
    public function fmt(string $val, int $width = 10, string $pad = " "): string {
        return str_pad($val, $width, $pad);
    }
}
$f = new Format;
echo $f->fmt("hi"), "|\n";
echo $f->fmt(val: "hi", pad: "-"), "|\n";
echo $f->fmt(val: "hi", width: 5, pad: "."), "|\n";

echo str_pad("a", length: 5, pad_string: "-"), "|\n";

function mid(int $a, int $b = 5, int $c = 50, int ...$rest): int {
    return $a + $b + $c + array_sum($rest);
}
echo mid(1), "\n";
echo mid(1, 2), "\n";
echo mid(1, 2, 3), "\n";
echo mid(1, 2, 3, 100, 200), "\n";
