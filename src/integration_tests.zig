const std = @import("std");
const parser = @import("pipeline/parser.zig");
const VM = @import("runtime/vm.zig").VM;

fn expectOutput(source: []const u8, expected: []const u8) !void {
    const alloc = std.testing.allocator;

    var ast = try parser.parse(alloc, source);
    defer ast.deinit();

    var result = try @import("pipeline/compiler.zig").compile(&ast, alloc);
    defer result.deinit();

    var vm = try VM.init(alloc);
    defer vm.deinit();
    try vm.interpret(&result);

    errdefer std.debug.print("\nexpected: \"{s}\"\n  actual: \"{s}\"\n", .{ expected, vm.output.items });
    try std.testing.expectEqualStrings(expected, vm.output.items);
}

// ==========================================================================
// basic operations
// ==========================================================================

test "echo integer" {
    try expectOutput("<?php echo 42;", "42");
}

test "echo string" {
    try expectOutput("<?php echo 'hello';", "hello");
}

test "echo true false null" {
    try expectOutput("<?php echo true;", "1");
    try expectOutput("<?php echo false;", "");
    try expectOutput("<?php echo null;", "");
}

test "arithmetic" {
    try expectOutput("<?php echo 2 + 3;", "5");
    try expectOutput("<?php echo 10 - 3;", "7");
    try expectOutput("<?php echo 4 * 5;", "20");
    try expectOutput("<?php echo 9 / 3;", "3");
    try expectOutput("<?php echo 10 % 3;", "1");
}

test "float arithmetic" {
    try expectOutput("<?php echo 1.5 + 2.5;", "4");
    try expectOutput("<?php echo 10 / 4;", "2.5");
}

test "negation" {
    try expectOutput("<?php echo -42;", "-42");
}

test "variable assignment and read" {
    try expectOutput("<?php $x = 42; echo $x;", "42");
}

test "compound assignment" {
    try expectOutput("<?php $x = 10; $x += 5; echo $x;", "15");
}

test "multiple variables" {
    try expectOutput("<?php $a = 3; $b = 4; echo $a + $b;", "7");
}

test "if true" {
    try expectOutput("<?php if (true) { echo 'yes'; }", "yes");
}

test "if false" {
    try expectOutput("<?php if (false) { echo 'yes'; }", "");
}

test "if else" {
    try expectOutput("<?php if (false) { echo 'a'; } else { echo 'b'; }", "b");
}

test "while loop" {
    try expectOutput("<?php $i = 0; while ($i < 3) { echo $i; $i++; }", "012");
}

test "for loop" {
    try expectOutput("<?php for ($i = 0; $i < 5; $i++) { echo $i; }", "01234");
}

test "comparison" {
    try expectOutput("<?php echo 1 < 2 ? 'y' : 'n';", "y");
    try expectOutput("<?php echo 2 < 1 ? 'y' : 'n';", "n");
}

test "logical and short circuit" {
    try expectOutput("<?php echo false && true ? 'y' : 'n';", "n");
    try expectOutput("<?php echo true && true ? 'y' : 'n';", "y");
}

test "logical or short circuit" {
    try expectOutput("<?php echo false || true ? 'y' : 'n';", "y");
    try expectOutput("<?php echo false || false ? 'y' : 'n';", "n");
}

test "null coalesce" {
    try expectOutput("<?php $x = null; echo $x ?? 'default';", "default");
    try expectOutput("<?php $x = 42; echo $x ?? 'default';", "42");
}

test "function call" {
    try expectOutput("<?php function add($a, $b) { return $a + $b; } echo add(3, 4);", "7");
}

test "function scoping" {
    try expectOutput("<?php $x = 100; function foo($x) { return $x + 1; } echo foo(42); echo $x;", "43100");
}

test "nested calls" {
    try expectOutput("<?php function double($n) { return $n * 2; } function quad($n) { return double(double($n)); } echo quad(3);", "12");
}

test "break in while" {
    try expectOutput("<?php $i = 0; while (true) { if ($i == 3) { break; } echo $i; $i++; }", "012");
}

test "echo multiple" {
    try expectOutput("<?php echo 'a', 'b', 'c';", "abc");
}

test "string concat" {
    try expectOutput("<?php echo 'hello' . ' ' . 'world';", "hello world");
}

test "pre increment" {
    try expectOutput("<?php $x = 5; echo ++$x;", "6");
}

test "post increment" {
    try expectOutput("<?php $x = 5; echo $x++;", "5");
    try expectOutput("<?php $x = 5; $x++; echo $x;", "6");
}

test "mixed html and php" {
    try expectOutput("Hello <?php echo 'World';", "Hello World");
}

test "do while" {
    try expectOutput("<?php $i = 0; do { echo $i; $i++; } while ($i < 3);", "012");
}

test "not operator" {
    try expectOutput("<?php echo !true ? 'y' : 'n';", "n");
    try expectOutput("<?php echo !false ? 'y' : 'n';", "y");
}

test "spaceship operator" {
    try expectOutput("<?php echo 1 <=> 2;", "-1");
    try expectOutput("<?php echo 2 <=> 2;", "0");
    try expectOutput("<?php echo 3 <=> 2;", "1");
}

test "fizzbuzz" {
    try expectOutput(
        \\<?php
        \\for ($i = 1; $i <= 15; $i++) {
        \\    if ($i % 15 == 0) { echo 'FizzBuzz'; }
        \\    elseif ($i % 3 == 0) { echo 'Fizz'; }
        \\    elseif ($i % 5 == 0) { echo 'Buzz'; }
        \\    else { echo $i; }
        \\}
    , "12Fizz4BuzzFizz78FizzBuzz11Fizz1314FizzBuzz");
}

// ==========================================================================
// arrays
// ==========================================================================

test "array literal" {
    try expectOutput("<?php $a = [1, 2, 3]; echo count($a);", "3");
}

test "array access" {
    try expectOutput("<?php $a = [10, 20, 30]; echo $a[1];", "20");
}

test "array set" {
    try expectOutput("<?php $a = [1, 2, 3]; $a[1] = 99; echo $a[1];", "99");
}

test "array with string keys" {
    try expectOutput("<?php $a = ['x' => 10, 'y' => 20]; echo $a['x'];", "10");
}

test "foreach" {
    try expectOutput("<?php $a = [1, 2, 3]; foreach ($a as $v) { echo $v; }", "123");
}

test "foreach with key" {
    try expectOutput("<?php $a = ['a' => 1, 'b' => 2]; foreach ($a as $k => $v) { echo $k . $v; }", "a1b2");
}

test "count" {
    try expectOutput("<?php echo count([]);", "0");
    try expectOutput("<?php echo count([1, 2, 3]);", "3");
}

test "strlen" {
    try expectOutput("<?php echo strlen('hello');", "5");
    try expectOutput("<?php echo strlen('');", "0");
}

test "is_array" {
    try expectOutput("<?php echo is_array([1]) ? 'y' : 'n';", "y");
    try expectOutput("<?php echo is_array(42) ? 'y' : 'n';", "n");
}

// ==========================================================================
// closures
// ==========================================================================

test "closure assigned to variable" {
    try expectOutput("<?php $add = function($a, $b) { return $a + $b; }; echo $add(3, 4);", "7");
}

test "closure passed to function" {
    try expectOutput(
        \\<?php
        \\function apply($fn, $val) { return $fn($val); }
        \\$double = function($x) { return $x * 2; };
        \\echo apply($double, 5);
    , "10");
}

test "arrow function" {
    try expectOutput("<?php $sq = fn($x) => $x * $x; echo $sq(6);", "36");
}

test "array_map" {
    try expectOutput(
        \\<?php
        \\$nums = [1, 2, 3];
        \\$doubled = array_map(function($x) { return $x * 2; }, $nums);
        \\foreach ($doubled as $v) { echo $v; }
    , "246");
}

test "array_filter" {
    try expectOutput(
        \\<?php
        \\$nums = [1, 2, 3, 4, 5];
        \\$even = array_filter($nums, function($x) { return $x % 2 == 0; });
        \\foreach ($even as $v) { echo $v; }
    , "24");
}

test "usort" {
    try expectOutput(
        \\<?php
        \\$a = [3, 1, 2];
        \\usort($a, function($a, $b) { return $a - $b; });
        \\foreach ($a as $v) { echo $v; }
    , "123");
}

test "array_map with arrow function" {
    try expectOutput(
        \\<?php
        \\$result = array_map(fn($x) => $x + 10, [1, 2, 3]);
        \\foreach ($result as $v) { echo $v . ' '; }
    , "11 12 13 ");
}

test "inline closure call" {
    try expectOutput("<?php echo (function($x) { return $x + 1; })(41);", "42");
}

test "named function as callback string" {
    try expectOutput(
        \\<?php
        \\function triple($x) { return $x * 3; }
        \\$result = array_map('triple', [1, 2, 3]);
        \\foreach ($result as $v) { echo $v; }
    , "369");
}

test "closure use clause" {
    try expectOutput(
        \\<?php
        \\$x = 10;
        \\$add = function($y) use ($x) { return $x + $y; };
        \\echo $add(5);
    , "15");
}

test "closure use multiple vars" {
    try expectOutput(
        \\<?php
        \\$a = 'hello';
        \\$b = ' world';
        \\$greet = function() use ($a, $b) { return $a . $b; };
        \\echo $greet();
    , "hello world");
}

test "closure use captures at creation time" {
    try expectOutput(
        \\<?php
        \\$x = 1;
        \\$fn = function() use ($x) { return $x; };
        \\$x = 99;
        \\echo $fn();
    , "1");
}

test "closure use with array_map" {
    try expectOutput(
        \\<?php
        \\$multiplier = 3;
        \\$result = array_map(function($x) use ($multiplier) { return $x * $multiplier; }, [1, 2, 3]);
        \\foreach ($result as $v) { echo $v . ' '; }
    , "3 6 9 ");
}

// ==========================================================================
// string interpolation
// ==========================================================================

test "string interpolation simple" {
    try expectOutput("<?php $name = 'World'; echo \"Hello $name\";", "Hello World");
}

test "string interpolation multiple" {
    try expectOutput("<?php $a = 'foo'; $b = 'bar'; echo \"$a and $b\";", "foo and bar");
}

test "string interpolation curly" {
    try expectOutput("<?php $x = 'test'; echo \"Value: {$x}!\";", "Value: test!");
}

test "string interpolation with expr after" {
    try expectOutput("<?php $n = 42; echo \"num=$n.\";", "num=42.");
}

test "string interpolation escaped dollar" {
    try expectOutput("<?php echo \"price is \\$5\";", "price is $5");
}

test "string interpolation array access" {
    try expectOutput("<?php $a = ['x', 'y']; echo \"val=$a[1]\";", "val=y");
}

test "string interpolation curly array" {
    try expectOutput("<?php $a = ['k' => 'v']; echo \"{$a['k']}\";", "v");
}

test "string no interpolation single quotes" {
    try expectOutput("<?php $x = 1; echo '$x';", "$x");
}

// ==========================================================================
// constants
// ==========================================================================

test "predefined constant PHP_EOL" {
    try expectOutput("<?php echo 'a' . PHP_EOL . 'b';", "a\nb");
}

test "predefined constant PHP_INT_MAX" {
    try expectOutput("<?php echo PHP_INT_MAX;", "9223372036854775807");
}

test "predefined constant STR_PAD_LEFT" {
    try expectOutput("<?php echo STR_PAD_LEFT;", "0");
}

test "predefined constant TRUE FALSE NULL" {
    try expectOutput("<?php echo TRUE;", "1");
    try expectOutput("<?php echo FALSE;", "");
    try expectOutput("<?php echo NULL;", "");
}

test "define constant" {
    try expectOutput("<?php define('FOO', 42); echo FOO;", "42");
}

test "const declaration" {
    try expectOutput("<?php const BAR = 'hello'; echo BAR;", "hello");
}

test "defined function" {
    try expectOutput("<?php define('X', 1); echo defined('X') ? 'y' : 'n';", "y");
    try expectOutput("<?php echo defined('NOPE') ? 'y' : 'n';", "n");
}

test "constant function" {
    try expectOutput("<?php define('VAL', 99); echo constant('VAL');", "99");
}

// ==========================================================================
// type casting
// ==========================================================================

test "cast int" {
    try expectOutput("<?php echo (int)'42';", "42");
    try expectOutput("<?php echo (int)3.7;", "3");
    try expectOutput("<?php echo (int)true;", "1");
    try expectOutput("<?php echo (int)false;", "0");
}

test "cast float" {
    try expectOutput("<?php echo (float)'3.14';", "3.14");
    try expectOutput("<?php echo (float)42;", "42");
}

test "cast string" {
    try expectOutput("<?php echo (string)42;", "42");
    try expectOutput("<?php echo (string)3.14;", "3.14");
    try expectOutput("<?php echo (string)true;", "1");
    try expectOutput("<?php echo (string)null;", "");
}

test "cast bool" {
    try expectOutput("<?php echo (bool)1 ? 'y' : 'n';", "y");
    try expectOutput("<?php echo (bool)0 ? 'y' : 'n';", "n");
    try expectOutput("<?php echo (bool)'' ? 'y' : 'n';", "n");
    try expectOutput("<?php echo (bool)'hello' ? 'y' : 'n';", "y");
}

test "cast array" {
    try expectOutput("<?php $a = (array)42; echo count($a); echo $a[0];", "142");
}

// ==========================================================================
// switch / match
// ==========================================================================

test "switch basic" {
    try expectOutput(
        \\<?php
        \\$x = 2;
        \\switch ($x) {
        \\    case 1: echo 'one'; break;
        \\    case 2: echo 'two'; break;
        \\    case 3: echo 'three'; break;
        \\}
    , "two");
}

test "switch default" {
    try expectOutput(
        \\<?php
        \\$x = 99;
        \\switch ($x) {
        \\    case 1: echo 'one'; break;
        \\    default: echo 'other'; break;
        \\}
    , "other");
}

test "switch fallthrough" {
    try expectOutput(
        \\<?php
        \\$x = 2;
        \\switch ($x) {
        \\    case 1:
        \\    case 2:
        \\    case 3:
        \\        echo 'low';
        \\        break;
        \\    default:
        \\        echo 'high';
        \\}
    , "low");
}

test "switch fallthrough no break" {
    try expectOutput(
        \\<?php
        \\$x = 1;
        \\switch ($x) {
        \\    case 1: echo 'a';
        \\    case 2: echo 'b';
        \\    case 3: echo 'c'; break;
        \\}
    , "abc");
}

test "switch no match no default" {
    try expectOutput(
        \\<?php
        \\$x = 99;
        \\switch ($x) {
        \\    case 1: echo 'one'; break;
        \\    case 2: echo 'two'; break;
        \\}
        \\echo 'done';
    , "done");
}

test "match basic" {
    try expectOutput(
        \\<?php
        \\$x = 2;
        \\echo match($x) { 1 => 'one', 2 => 'two', 3 => 'three' };
    , "two");
}

test "match default" {
    try expectOutput(
        \\<?php
        \\$x = 99;
        \\echo match($x) { 1 => 'one', default => 'other' };
    , "other");
}

test "match multi value" {
    try expectOutput(
        \\<?php
        \\$x = 2;
        \\echo match($x) { 1, 2, 3 => 'low', 4, 5 => 'high', default => '?' };
    , "low");
}

test "match no match returns null" {
    try expectOutput(
        \\<?php
        \\$r = match(99) { 1 => 'one' };
        \\echo $r === null ? 'null' : 'value';
    , "null");
}

test "match assigned to variable" {
    try expectOutput(
        \\<?php
        \\$x = 'b';
        \\$result = match($x) { 'a' => 1, 'b' => 2, 'c' => 3 };
        \\echo $result;
    , "2");
}

// ==========================================================================
// classes
// ==========================================================================

test "class basic instantiation" {
    try expectOutput(
        \\<?php
        \\class Foo {
        \\    public function hello() {
        \\        echo 'hi';
        \\    }
        \\}
        \\$f = new Foo();
        \\$f->hello();
    , "hi");
}

test "class constructor" {
    try expectOutput(
        \\<?php
        \\class Person {
        \\    public $name;
        \\    public function __construct($n) {
        \\        $this->name = $n;
        \\    }
        \\    public function greet() {
        \\        echo 'Hello ' . $this->name;
        \\    }
        \\}
        \\$p = new Person('Alice');
        \\$p->greet();
    , "Hello Alice");
}

test "class property access" {
    try expectOutput(
        \\<?php
        \\class Box {
        \\    public $value;
        \\    public function __construct($v) {
        \\        $this->value = $v;
        \\    }
        \\}
        \\$b = new Box(42);
        \\echo $b->value;
    , "42");
}

test "class property default" {
    try expectOutput(
        \\<?php
        \\class Counter {
        \\    public $count = 0;
        \\    public function inc() {
        \\        $this->count = $this->count + 1;
        \\    }
        \\    public function get() {
        \\        return $this->count;
        \\    }
        \\}
        \\$c = new Counter();
        \\$c->inc();
        \\$c->inc();
        \\$c->inc();
        \\echo $c->get();
    , "3");
}

test "class multiple instances" {
    try expectOutput(
        \\<?php
        \\class Dog {
        \\    public $name;
        \\    public function __construct($n) {
        \\        $this->name = $n;
        \\    }
        \\}
        \\$a = new Dog('Rex');
        \\$b = new Dog('Spot');
        \\echo $a->name . ' ' . $b->name;
    , "Rex Spot");
}

test "class method with return value" {
    try expectOutput(
        \\<?php
        \\class Math {
        \\    public function add($a, $b) {
        \\        return $a + $b;
        \\    }
        \\}
        \\$m = new Math();
        \\echo $m->add(3, 4);
    , "7");
}

test "class method chaining state" {
    try expectOutput(
        \\<?php
        \\class Acc {
        \\    public $val = 0;
        \\    public function add($n) {
        \\        $this->val = $this->val + $n;
        \\    }
        \\}
        \\$a = new Acc();
        \\$a->add(10);
        \\$a->add(20);
        \\echo $a->val;
    , "30");
}

test "class new without parens" {
    try expectOutput(
        \\<?php
        \\class Empty2 {}
        \\$e = new Empty2;
        \\echo $e !== null ? 'ok' : 'fail';
    , "ok");
}

test "class gettype" {
    try expectOutput(
        \\<?php
        \\class Foo {}
        \\$f = new Foo();
        \\echo gettype($f);
    , "object");
}

// ==========================================================================
// inheritance
// ==========================================================================

test "inherited method" {
    try expectOutput(
        \\<?php
        \\class Base {
        \\    public function greet() { return 'hello'; }
        \\}
        \\class Child extends Base {}
        \\$c = new Child();
        \\echo $c->greet();
    , "hello");
}

test "inherited constructor" {
    try expectOutput(
        \\<?php
        \\class Animal {
        \\    public $name;
        \\    public function __construct($n) { $this->name = $n; }
        \\}
        \\class Dog extends Animal {}
        \\$d = new Dog('Rex');
        \\echo $d->name;
    , "Rex");
}

test "method override" {
    try expectOutput(
        \\<?php
        \\class Animal {
        \\    public function sound() { return 'generic'; }
        \\}
        \\class Cat extends Animal {
        \\    public function sound() { return 'meow'; }
        \\}
        \\$c = new Cat();
        \\echo $c->sound();
    , "meow");
}

test "parent method call" {
    try expectOutput(
        \\<?php
        \\class Base {
        \\    public function val() { return 'base'; }
        \\}
        \\class Child extends Base {
        \\    public function val() { return parent::val() . '+child'; }
        \\}
        \\$c = new Child();
        \\echo $c->val();
    , "base+child");
}

test "parent constructor call" {
    try expectOutput(
        \\<?php
        \\class Shape {
        \\    public $color;
        \\    public function __construct($c) { $this->color = $c; }
        \\}
        \\class Circle extends Shape {
        \\    public $radius;
        \\    public function __construct($c, $r) {
        \\        parent::__construct($c);
        \\        $this->radius = $r;
        \\    }
        \\}
        \\$c = new Circle('red', 5);
        \\echo $c->color . ' ' . $c->radius;
    , "red 5");
}

test "multi-level inheritance" {
    try expectOutput(
        \\<?php
        \\class A {
        \\    public function id() { return 'A'; }
        \\}
        \\class B extends A {
        \\    public function id() { return parent::id() . 'B'; }
        \\}
        \\class C extends B {
        \\    public function id() { return parent::id() . 'C'; }
        \\}
        \\$c = new C();
        \\echo $c->id();
    , "ABC");
}

test "inherited property defaults" {
    try expectOutput(
        \\<?php
        \\class Config {
        \\    public $debug = 0;
        \\}
        \\class AppConfig extends Config {
        \\    public $name = 'app';
        \\}
        \\$c = new AppConfig();
        \\echo $c->debug . ' ' . $c->name;
    , "0 app");
}

// ==========================================================================
// exceptions
// ==========================================================================

test "basic throw catch" {
    try expectOutput(
        \\<?php
        \\try {
        \\    throw new Exception('oops');
        \\} catch (Exception $e) {
        \\    echo $e->getMessage();
        \\}
    , "oops");
}

test "catch skips remaining try body" {
    try expectOutput(
        \\<?php
        \\try {
        \\    echo 'before ';
        \\    throw new Exception('err');
        \\    echo 'after ';
        \\} catch (Exception $e) {
        \\    echo 'caught';
        \\}
    , "before caught");
}

test "code after try catch runs" {
    try expectOutput(
        \\<?php
        \\try {
        \\    throw new Exception('x');
        \\} catch (Exception $e) {
        \\    echo 'caught ';
        \\}
        \\echo 'done';
    , "caught done");
}

test "typed catch matching" {
    try expectOutput(
        \\<?php
        \\try {
        \\    throw new RuntimeException('rt');
        \\} catch (InvalidArgumentException $e) {
        \\    echo 'wrong';
        \\} catch (RuntimeException $e) {
        \\    echo $e->getMessage();
        \\}
    , "rt");
}

test "parent class catch" {
    try expectOutput(
        \\<?php
        \\try {
        \\    throw new RuntimeException('child');
        \\} catch (Exception $e) {
        \\    echo $e->getMessage();
        \\}
    , "child");
}

test "nested try catch propagation" {
    try expectOutput(
        \\<?php
        \\try {
        \\    try {
        \\        throw new Exception('inner');
        \\    } catch (RuntimeException $e) {
        \\        echo 'wrong';
        \\    }
        \\} catch (Exception $e) {
        \\    echo $e->getMessage();
        \\}
    , "inner");
}

test "finally runs on normal path" {
    try expectOutput(
        \\<?php
        \\try {
        \\    echo 'try ';
        \\} finally {
        \\    echo 'finally';
        \\}
    , "try finally");
}

test "finally runs on exception path" {
    try expectOutput(
        \\<?php
        \\try {
        \\    throw new Exception('x');
        \\} catch (Exception $e) {
        \\    echo 'catch ';
        \\} finally {
        \\    echo 'finally';
        \\}
    , "catch finally");
}

test "exception getMessage and getCode" {
    try expectOutput(
        \\<?php
        \\$e = new Exception('msg', 42);
        \\echo $e->getMessage() . ' ' . $e->getCode();
    , "msg 42");
}

test "throw in function caught by caller" {
    try expectOutput(
        \\<?php
        \\function risky() {
        \\    throw new Exception('boom');
        \\}
        \\try {
        \\    risky();
        \\} catch (Exception $e) {
        \\    echo $e->getMessage();
        \\}
    , "boom");
}

test "fiber basic start suspend resume" {
    try expectOutput(
        \\<?php
        \\$fiber = new Fiber(function() {
        \\    Fiber::suspend('first');
        \\    return 'done';
        \\});
        \\echo $fiber->start();
        \\echo " ";
        \\$fiber->resume();
        \\echo $fiber->getReturn();
    , "first done");
}

test "fiber deep suspension" {
    try expectOutput(
        \\<?php
        \\function inner() { Fiber::suspend('deep'); }
        \\function middle() { inner(); }
        \\$f = new Fiber(function() { middle(); return 'ok'; });
        \\echo $f->start();
        \\echo " ";
        \\$f->resume();
        \\echo $f->getReturn();
    , "deep ok");
}

test "fiber resume value" {
    try expectOutput(
        \\<?php
        \\$f = new Fiber(function() {
        \\    $v = Fiber::suspend();
        \\    echo $v;
        \\});
        \\$f->start();
        \\$f->resume('hello');
    , "hello");
}

test "fiber multiple cycles" {
    try expectOutput(
        \\<?php
        \\$f = new Fiber(function() {
        \\    $sum = 0;
        \\    for ($i = 0; $i < 3; $i++) {
        \\        $val = Fiber::suspend($sum);
        \\        $sum += $val;
        \\    }
        \\    return $sum;
        \\});
        \\echo $f->start() . " ";
        \\echo $f->resume(10) . " ";
        \\echo $f->resume(20) . " ";
        \\$f->resume(30);
        \\echo $f->getReturn();
    , "0 10 30 60");
}

test "fiber start with args" {
    try expectOutput(
        \\<?php
        \\$f = new Fiber(function($a, $b) {
        \\    return $a + $b;
        \\});
        \\$f->start(3, 4);
        \\echo $f->getReturn();
    , "7");
}

test "pdo sqlite basic" {
    try expectOutput(
        \\<?php
        \\$pdo = new PDO('sqlite::memory:');
        \\$pdo->exec("CREATE TABLE t (id INTEGER PRIMARY KEY, val TEXT)");
        \\$pdo->exec("INSERT INTO t (val) VALUES ('hello')");
        \\$stmt = $pdo->query("SELECT val FROM t");
        \\$row = $stmt->fetch(PDO::FETCH_ASSOC);
        \\echo $row['val'];
    , "hello");
}

test "pdo sqlite prepared params" {
    try expectOutput(
        \\<?php
        \\$pdo = new PDO('sqlite::memory:');
        \\$pdo->exec("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)");
        \\$stmt = $pdo->prepare("INSERT INTO t (name) VALUES (?)");
        \\$stmt->execute(['alice']);
        \\$stmt->execute(['bob']);
        \\$stmt = $pdo->query("SELECT name FROM t ORDER BY id");
        \\$rows = $stmt->fetchAll(PDO::FETCH_ASSOC);
        \\echo $rows[0]['name'] . " " . $rows[1]['name'];
    , "alice bob");
}

test "pdo sqlite transactions" {
    try expectOutput(
        \\<?php
        \\$pdo = new PDO('sqlite::memory:');
        \\$pdo->exec("CREATE TABLE t (id INTEGER PRIMARY KEY, val TEXT)");
        \\$pdo->exec("INSERT INTO t (val) VALUES ('keep')");
        \\$pdo->beginTransaction();
        \\$pdo->exec("DELETE FROM t");
        \\$pdo->rollBack();
        \\$stmt = $pdo->query("SELECT val FROM t");
        \\echo $stmt->fetchColumn();
    , "keep");
}

test "throw in method caught by caller" {
    try expectOutput(
        \\<?php
        \\class Svc {
        \\    public function run() {
        \\        throw new Exception('fail');
        \\    }
        \\}
        \\try {
        \\    $s = new Svc();
        \\    $s->run();
        \\} catch (Exception $e) {
        \\    echo $e->getMessage();
        \\}
    , "fail");
}
