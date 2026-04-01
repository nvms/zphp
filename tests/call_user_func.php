<?php

// test 1: call_user_func with string callable
function double($n) { return $n * 2; }
echo call_user_func('double', 5) . "\n"; // 10

// test 2: call_user_func with static method
class MathHelper {
    public static function triple($n) { return $n * 3; }
    public function square($n) { return $n * $n; }
}
echo call_user_func('MathHelper::triple', 4) . "\n"; // 12

// test 3: call_user_func with [object, method] array
$helper = new MathHelper();
echo call_user_func([$helper, 'square'], 5) . "\n"; // 25

// test 4: call_user_func with [ClassName, staticMethod] array
echo call_user_func(['MathHelper', 'triple'], 6) . "\n"; // 18

// test 5: call_user_func_array with string callable
echo call_user_func_array('double', [7]) . "\n"; // 14

// test 6: call_user_func_array with [object, method]
echo call_user_func_array([$helper, 'square'], [8]) . "\n"; // 64

// test 7: call_user_func with closure
$add = function($a, $b) { return $a + $b; };
echo call_user_func($add, 3, 4) . "\n"; // 7

// test 8: array_map with closure
$nums = [1, 2, 3, 4];
$doubled = array_map(function($n) { return $n * 2; }, $nums);
echo implode(',', $doubled) . "\n"; // 2,4,6,8

// test 9: array_map with [object, method]
$mapped = array_map([$helper, 'square'], $nums);
echo implode(',', $mapped) . "\n"; // 1,4,9,16

// test 10: array_filter with closure
$evens = array_filter($nums, function($n) { return $n % 2 === 0; });
echo implode(',', $evens) . "\n"; // 2,4

// test 11: usort with closure
$arr = [3, 1, 4, 1, 5];
usort($arr, function($a, $b) { return $a - $b; });
echo implode(',', $arr) . "\n"; // 1,1,3,4,5

// test 12: is_callable checks
echo var_export(is_callable('double'), true) . "\n"; // true
echo var_export(is_callable([$helper, 'square']), true) . "\n"; // true
echo var_export(is_callable(['MathHelper', 'triple']), true) . "\n"; // true
echo var_export(is_callable('nonexistent'), true) . "\n"; // false
echo var_export(is_callable([$helper, 'nonexistent']), true) . "\n"; // false

// test 12b: is_callable with __invoke
class Invokable {
    public function __invoke(int $x): int { return $x * 2; }
}
$inv = new Invokable();
echo var_export(is_callable($inv), true) . "\n"; // true
echo $inv(5) . "\n"; // 10

class NotInvokable {
    public function run(): void {}
}
echo var_export(is_callable(new NotInvokable()), true) . "\n"; // false

// test 13: array_reduce with closure
$sum = array_reduce($nums, function($carry, $item) { return $carry + $item; }, 0);
echo $sum . "\n"; // 10

// test 14: call_user_func with $this access
class Counter {
    public $count = 0;
    public function increment() {
        $this->count++;
        return $this->count;
    }
}
$counter = new Counter();
echo call_user_func([$counter, 'increment']) . "\n"; // 1
echo call_user_func([$counter, 'increment']) . "\n"; // 2
echo $counter->count . "\n"; // 2

// test 15: multiple args with call_user_func
function add($a, $b, $c) { return $a + $b + $c; }
echo call_user_func('add', 10, 20, 30) . "\n"; // 60
