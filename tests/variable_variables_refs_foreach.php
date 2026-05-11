<?php
$name = "x";
$$name = 42;
echo $x, "\n";

$a = "name";
$$a = "alice";
echo $name, "\n";

$varname = "msg";
$$varname = "hello";
echo $msg, "\n";

$pairs = ["foo", "bar", "baz"];
foreach ($pairs as $i => $v) {
    $$v = $i;
}
echo "$foo $bar $baz\n";

$nums = [1, 2, 3, 4];
foreach ($nums as &$n) $n *= 2;
unset($n);
print_r($nums);

$nums = [1, 2, 3];
foreach ($nums as $i => &$n) {
    $n = $i + 10;
}
unset($n);
print_r($nums);

$arr = ["a" => 1, "b" => 2];
foreach ($arr as $k => &$v) {
    $v = strtoupper($k) . "=" . $v;
}
unset($v);
print_r($arr);

function modify(&$x) { $x = 99; }
$val = 1;
modify($val);
echo $val, "\n";

function modifyArr(&$arr, $i, $v) { $arr[$i] = $v; }
$arr = [10, 20, 30];
modifyArr($arr, 1, 999);
print_r($arr);

$nums = [1, 2, 3];
$copy = $nums;
$copy[0] = 99;
echo $nums[0], " ", $copy[0], "\n";

class Container {
    public array $items = [];
}
$c = new Container;
$c->items = [1, 2, 3];
function setItem(Container $c, int $i, mixed $v): void {
    $c->items[$i] = $v;
}
setItem($c, 0, 99);
print_r($c->items);

$counter = 0;
function inc(&$x) { $x++; }
inc($counter);
inc($counter);
inc($counter);
echo $counter, "\n";

$arr = [1, 2, 3];
function passByVal($x) { $x[] = 99; }
function passByRef(&$x) { $x[] = 99; }
passByVal($arr);
print_r($arr);
passByRef($arr);
print_r($arr);

$arr = ["a", "b", "c"];
function clearItem(&$item) { $item = null; }
clearItem($arr[1]);
print_r($arr);

$varname = "dynamic";
$$varname = 42;
echo $dynamic, "\n";

class Obj {
    public string $field = "init";
}
$o = new Obj;
$name = "field";
$o->$name = "modified";
echo $o->field, "\n";

$prefix = "user";
$$prefix = "alice";
echo $user, "\n";

function refSquare(int &$x): void { $x = $x * $x; }
$n = 5;
refSquare($n);
echo $n, "\n";

function refSwap(int &$a, int &$b): void {
    $t = $a;
    $a = $b;
    $b = $t;
}
$x = 1;
$y = 2;
refSwap($x, $y);
echo $x, " ", $y, "\n";

$nums = [3, 1, 4, 1, 5];
function appendVal(array &$a, int $v): void { $a[] = $v; }
appendVal($nums, 99);
print_r($nums);

class Counter {
    public int $val = 0;
}
$c = new Counter;
function bump(Counter $c): void { $c->val++; }
bump($c);
bump($c);
echo $c->val, "\n";

$keys = ["alpha", "beta", "gamma"];
$values = [];
foreach ($keys as $k) {
    $$k = strlen($k);
    $values[] = $$k;
}
print_r($values);
echo $alpha, " ", $beta, " ", $gamma, "\n";
