<?php
// iterator_to_array on Generator with same keys
function gen_dup() { yield 1; yield 1; yield 2; yield 3; yield 3; }
$g = gen_dup();
print_r(iterator_to_array($g));
print_r(iterator_to_array(gen_dup(), false));
print_r(iterator_to_array(gen_dup(), true));

// generator with explicit keys collisions
function gen_keyed() {
    yield 'a' => 1;
    yield 'b' => 2;
    yield 'a' => 3;
    yield 'c' => 4;
}
print_r(iterator_to_array(gen_keyed()));
print_r(iterator_to_array(gen_keyed(), true));
print_r(iterator_to_array(gen_keyed(), false));

// numeric collisions
function gen_num() { yield 0 => 'a'; yield 1 => 'b'; yield 0 => 'c'; }
print_r(iterator_to_array(gen_num()));
print_r(iterator_to_array(gen_num(), false));

// yield from with collisions
function gen_outer() {
    yield 'x' => 1;
    yield from gen_keyed();
    yield 'y' => 99;
}
print_r(iterator_to_array(gen_outer()));

// SplObjectStorage
$s = new SplObjectStorage();
$a = new stdClass; $a->n = 1;
$b = new stdClass; $b->n = 2;
$c = new stdClass; $c->n = 3;
$s[$a] = "info-a";
$s[$b] = "info-b";
$s->offsetSet($c, "info-c");
echo count($s), "\n";
echo $s[$a], " ", $s[$b], "\n";
foreach ($s as $obj) {
    echo $obj->n, "=", $s[$obj], " ";
}
echo "\n";
$s->offsetUnset($b);
echo count($s), "\n";
var_dump($s->offsetExists($b));
var_dump($s->offsetExists($a));
$s->offsetUnset($a);
echo count($s), "\n";

// named args
function greet(string $greeting = "Hello", string $name = "World", string $punct = "!") {
    return "$greeting, $name$punct";
}
echo greet(), "\n";
echo greet(name: "PHP"), "\n";
echo greet(punct: ".", name: "Bob"), "\n";
echo greet("Hi", punct: "?"), "\n";
echo greet(name: "Z", greeting: "Yo"), "\n";

// named args with array_*
function named_func($a, $b = 2, $c = 3) {
    return "$a-$b-$c";
}
echo named_func(a: 1), "\n";
echo named_func(a: 1, c: 30), "\n";
echo named_func(c: 30, a: 1, b: 20), "\n";

// strict types with named
function takes_int(int $x = 5) { return $x; }
echo takes_int(x: 10), "\n";

// spread + named
function spread_test($a, $b, $c) { return "$a,$b,$c"; }
echo spread_test(...[1, 2, 3]), "\n";
echo spread_test(...["a" => 1, "b" => 2, "c" => 3]), "\n";
echo spread_test(1, ...["b" => 2, "c" => 3]), "\n";
