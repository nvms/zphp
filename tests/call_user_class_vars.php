<?php
// call_user_func variants
echo call_user_func("strtoupper", "hello"), "\n";
echo call_user_func(fn($x) => $x * 2, 5), "\n";

class C {
    public function inst($a, $b) { return "$a+$b"; }
    public static function stat($a) { return "stat:$a"; }
}
$c = new C;
echo call_user_func([$c, "inst"], 1, 2), "\n";
echo call_user_func(["C", "stat"], 9), "\n";
echo call_user_func("C::stat", 7), "\n";

// call_user_func_array
echo call_user_func_array("strlen", ["hello"]), "\n";
echo call_user_func_array([$c, "inst"], [3, 4]), "\n";
echo call_user_func_array("C::stat", [11]), "\n";
echo call_user_func_array(fn(...$a) => array_sum($a), [1, 2, 3, 4, 5]), "\n";

// callable with named args (PHP 8.0+)
print_r(call_user_func_array("range", ["start" => 0, "end" => 5]));
print_r(call_user_func_array("range", [1, 5, 1]));

// Closure::fromCallable static
$cb = Closure::fromCallable(["C", "stat"]);
echo $cb(42), "\n";
$cb2 = Closure::fromCallable([$c, "inst"]);
echo $cb2(5, 6), "\n";
$cb3 = Closure::fromCallable("strtoupper");
echo $cb3("hi"), "\n";

// ReflectionMethod::invoke
$rm = new ReflectionMethod(C::class, "inst");
echo $rm->invoke($c, 7, 8), "\n";
echo $rm->invokeArgs($c, [9, 10]), "\n";
$rms = new ReflectionMethod(C::class, "stat");
echo $rms->invoke(null, 1), "\n";
echo $rms->invokeArgs(null, [2]), "\n";

// dynamic method names
class D {
    public function foo() { return "foo"; }
    public function bar() { return "bar"; }
}
$d = new D;
$m = "foo";
echo $d->$m(), "\n";
$m2 = "bar";
echo $d->{$m2}(), "\n";
$names = ["foo", "bar"];
foreach ($names as $n) echo $d->$n(), " ";
echo "\n";

// variable variables
$name = "x";
$$name = 42;
echo $x, "\n";
$keys = ["a", "b", "c"];
foreach ($keys as $k) $$k = strlen($k) * 10;
echo "$a $b $c\n";

// get_class_vars
class E {
    public int $a = 1;
    protected string $b = "hi";
    private float $c = 3.14;
    public static int $st = 99;
}
print_r(get_class_vars(E::class));

// get_class_methods
class F {
    public function pub() {}
    protected function prot() {}
    private function priv() {}
    public static function statM() {}
}
$m = get_class_methods(F::class); sort($m); print_r($m);
class G extends F {
    public function child() {}
    private function priv2() {}
}
$m = get_class_methods(G::class); sort($m); print_r($m);

// parent:: from inherited static
class P {
    public static function hello(): string { return "P::hello"; }
    public static function call(): string { return static::class . " calling"; }
}
class Q extends P {
    public static function hello(): string { return parent::hello() . "+Q"; }
}
echo Q::hello(), "\n";
echo P::call(), " ", Q::call(), "\n";

// usort with [$obj, 'method'] callable
class Sorter {
    public function asc($a, $b) { return $a <=> $b; }
    public function desc($a, $b) { return $b <=> $a; }
}
$s = new Sorter;
$arr = [3, 1, 4, 1, 5, 9, 2, 6];
$copy = $arr; usort($copy, [$s, "asc"]); print_r($copy);
$copy = $arr; usort($copy, [$s, "desc"]); print_r($copy);

// usort with static method
class StaticSorter { public static function rev($a, $b) { return $b <=> $a; } }
$copy = $arr; usort($copy, ["StaticSorter", "rev"]); print_r($copy);
$copy = $arr; usort($copy, "StaticSorter::rev"); print_r($copy);

// number_format with non-default thousand sep
echo number_format(1234567.89, 2, '.', ','), "\n";
echo number_format(1234567.89, 2, ',', '.'), "\n";
echo number_format(1234567.89, 2, ',', ' '), "\n";
echo number_format(1234567.89, 2, '.', ''), "\n";
echo number_format(1234567.89, 2, ',', "'"), "\n";
echo number_format(1000.5, 0, '.', ','), "\n"; // banker's rounding: 1,000 (or 1,001? PHP rounds half-up: 1,001)
echo number_format(0.5, 0), "\n"; // PHP: 1
echo number_format(1.5, 0), "\n"; // PHP: 2

// array_search with closure - oh wait array_search doesn't take callback
// instead use array_filter with key
$found_key = array_search(3, [1, 2, 3, 4]);
echo $found_key, "\n";
