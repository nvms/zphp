<?php

// basic scalar types
function add_ints(int $a, int $b): int {
    return $a + $b;
}
echo add_ints(3, 4) . "\n";

// float accepts int (widening)
function double_it(float $x): float {
    return $x * 2;
}
echo double_it(5) . "\n";
echo double_it(2.5) . "\n";

// string type
function greet(string $name): string {
    return "hello " . $name;
}
echo greet("world") . "\n";

// bool type
function negate(bool $val): bool {
    return !$val;
}
echo var_export(negate(true), true) . "\n";
echo var_export(negate(false), true) . "\n";

// nullable types
function maybe_int(?int $x): ?int {
    return $x;
}
echo maybe_int(42) . "\n";
echo var_export(maybe_int(null), true) . "\n";

// union types
function int_or_string(int|string $val): string {
    return "got: " . $val;
}
echo int_or_string(42) . "\n";
echo int_or_string("hello") . "\n";

// void return
function do_nothing(): void {
    // nothing
}
do_nothing();
echo "void ok\n";

// mixed accepts anything
function accept_mixed(mixed $val): mixed {
    return $val;
}
echo accept_mixed(42) . "\n";
echo accept_mixed("hi") . "\n";

// array type
function first_element(array $arr): mixed {
    return $arr[0];
}
echo first_element([10, 20, 30]) . "\n";

// callable type
function apply(callable $fn, int $x): int {
    return $fn($x);
}
echo apply(function($n) { return $n * 3; }, 7) . "\n";

// class types with inheritance
class Animal {
    public string $name;
    public function __construct(string $name) {
        $this->name = $name;
    }
}

class Dog extends Animal {}

function get_name(Animal $a): string {
    return $a->name;
}
echo get_name(new Animal("cat")) . "\n";
echo get_name(new Dog("rex")) . "\n";

// TypeError catching - wrong param type
try {
    add_ints("not", "ints");
} catch (\TypeError $e) {
    $msg = $e->getMessage();
    $pos = strpos($msg, ", called in");
    if ($pos !== false) $msg = substr($msg, 0, $pos);
    echo "caught: " . $msg . "\n";
}

// TypeError catching - wrong return type
function should_return_int(): int {
    return "oops";
}
try {
    should_return_int();
} catch (\TypeError $e) {
    echo "caught: " . $e->getMessage() . "\n";
}

// multiple params, partial typing
function partial(int $a, $b): string {
    return $a . ":" . $b;
}
echo partial(1, "anything") . "\n";
echo partial(2, 99) . "\n";

// iterable type
function sum_iterable(iterable $items): int {
    $sum = 0;
    foreach ($items as $item) {
        $sum += $item;
    }
    return $sum;
}
echo sum_iterable([1, 2, 3]) . "\n";

// object type
function get_class_name(object $obj): string {
    return get_class($obj);
}
echo get_class_name(new Animal("test")) . "\n";

// true/false literal types
function must_be_true(true $val): true {
    return $val;
}
echo var_export(must_be_true(true), true) . "\n";

echo "done\n";
