<?php
// operator precedence edge cases that PHP gets right but naive parsers get wrong

// ! vs instanceof (! has lower precedence than instanceof)
class Foo {}
class Bar {}
$obj = new Foo();
echo "!obj instanceof Bar: " . var_export(!$obj instanceof Bar, true) . "\n";
echo "!obj instanceof Foo: " . var_export(!$obj instanceof Foo, true) . "\n";
echo "!(obj instanceof Bar): " . var_export(!($obj instanceof Bar), true) . "\n";

// ! vs comparison operators
$x = 5;
echo "!x == 5: " . var_export(!$x == 5, true) . "\n";
echo "!x === 0: " . var_export(!$x === 0, true) . "\n";

// not-instanceof with null
$null = null;
echo "!null instanceof Foo: " . var_export(!$null instanceof Foo, true) . "\n";

// instanceof in ternary
echo "obj instanceof Foo ? yes : no: " . ($obj instanceof Foo ? "yes" : "no") . "\n";
echo "obj instanceof Bar ? yes : no: " . ($obj instanceof Bar ? "yes" : "no") . "\n";

// instanceof with negation in condition
if (!$obj instanceof Bar) {
    echo "correct: obj is not Bar\n";
}

// assignment in comparison (inline assign)
if (false === $val = 5) {
    echo "wrong\n";
} else {
    echo "inline assign val=$val\n";
}

// assignment vs equality - right-to-left
$a = $b = $c = 10;
echo "chain assign: a=$a b=$b c=$c\n";

// ternary associativity (left-to-right in PHP 7, deprecated in PHP 8)
// PHP 8.x: nested ternary without parentheses is a parse error
// but single level should work:
$v = true ? "a" : "b";
echo "ternary: $v\n";

// null coalescing has lower precedence than comparison
$arr = ['key' => 0];
$result = $arr['key'] ?? 'default';
echo "null_coalesce existing: $result\n";
$result2 = $arr['missing'] ?? 'default';
echo "null_coalesce missing: $result2\n";

// null coalescing assignment
$x = null;
$x ??= 42;
echo "null_coalesce_assign: $x\n";
$x ??= 99;
echo "null_coalesce_assign_no_overwrite: $x\n";

// spaceship with arithmetic
echo "spaceship: " . (1 + 2 <=> 2 + 1) . "\n";
echo "spaceship2: " . (1 + 2 <=> 2 + 2) . "\n";

// logical and/or vs && / || precedence
// && has higher precedence than ||
$r = false || true && false;
echo "false || true && false: " . var_export($r, true) . "\n";

// 'and'/'or' have very low precedence (below assignment)
$r2 = true or false;
echo "true or false: " . var_export($r2, true) . "\n";

// concatenation vs comparison
echo "concat vs eq: " . var_export("a" . "b" == "ab", true) . "\n";
echo "concat vs eq2: " . var_export("a" . "b" === "ab", true) . "\n";

// arithmetic vs bitwise
echo "arith vs bitwise: " . (2 + 3 & 4) . "\n";
echo "arith vs bitwise2: " . (2 | 3 + 4) . "\n";

// unary minus vs power
echo "neg power: " . (-2 ** 2) . "\n";
echo "neg power parens: " . ((-2) ** 2) . "\n";

// cast vs arithmetic
echo "cast: " . ((int)"3" + 2) . "\n";
echo "cast2: " . ((float)"3.5" * 2) . "\n";

// not vs comparison
echo "not_cmp: " . var_export(!true == false, true) . "\n";
echo "not_cmp2: " . var_export(!false == true, true) . "\n";

// string concatenation chaining with method calls
class Str {
    public function val() { return "hello"; }
}
$s = new Str();
echo "method concat: " . $s->val() . " world\n";

// instanceof with ! and &&
$fooObj = new Foo();
if (!$fooObj instanceof Bar && $fooObj instanceof Foo) {
    echo "combined instanceof: correct\n";
}

// func_num_args through call chain
function innerA($a = null) {
    return func_num_args();
}
function outerA() {
    return innerA();
}
function outerB($x) {
    return innerA();
}
echo "fna_direct_0: " . innerA() . "\n";
echo "fna_direct_1: " . innerA("x") . "\n";
echo "fna_through_0: " . outerA() . "\n";
echo "fna_through_1: " . outerB("x") . "\n";

// static method with func_num_args
class Counter {
    public static function outer(string $s): int {
        return static::inner();
    }
    protected static function inner($x = null): int {
        return func_num_args();
    }
}
echo "static_fna_0: " . Counter::outer("test") . "\n";

class Wrapper {
    public function go() {
        return Counter::outer("test");
    }
}
echo "static_fna_through_0: " . (new Wrapper())->go() . "\n";

// at-sign error suppression precedence
echo "at_suppress: " . @strlen("hello") . "\n";

// power associativity (right-to-left)
echo "power_assoc: " . (2 ** 3 ** 2) . "\n";

// comparison chaining
echo "cmp_chain: " . var_export(1 < 2, true) . "\n";
echo "cmp_chain2: " . var_export(1 == 1, true) . "\n";

// bitwise shift vs addition
echo "shift_add: " . (1 << 2 + 1) . "\n";
echo "shift_add2: " . ((1 << 2) + 1) . "\n";
