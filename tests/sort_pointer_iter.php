<?php
// sort/usort/asort reset internal pointer
$a = [3, 1, 2];
next($a);
sort($a);
echo current($a), "\n"; // 1

$a = [3, 1, 2];
next($a);
usort($a, fn($x, $y) => $x <=> $y);
echo current($a), "\n";

$a = ['b' => 2, 'a' => 1, 'c' => 3];
next($a);
asort($a);
echo current($a), "\n"; // 1

$a = ['c' => 3, 'a' => 1, 'b' => 2];
next($a);
ksort($a);
echo current($a), "\n";

// count recursive
$arr = [1, 2, [3, 4, [5, 6]], 7];
echo count($arr), "\n";
echo count($arr, COUNT_NORMAL), "\n";
echo count($arr, COUNT_RECURSIVE), "\n";

$a = [[1,2,3], [4,5], [6]];
echo count($a, COUNT_RECURSIVE), "\n";

// count on Countable
class MyC implements Countable {
    public function count(): int { return 42; }
}
echo count(new MyC), "\n";

// current/next/prev/reset/end
$a = ['a', 'b', 'c'];
echo current($a), "\n";
echo next($a), "\n";
echo current($a), "\n";
echo prev($a), "\n";
echo reset($a), "\n";
echo end($a), "\n";
var_dump(next($a));
var_dump(current($a));

// key()
$a = ['x' => 1, 'y' => 2, 'z' => 3];
reset($a);
echo key($a), "\n";
next($a);
echo key($a), "\n";

// in_array with objects
$o1 = new stdClass; $o1->n = 1;
$o2 = new stdClass; $o2->n = 1;
$arr = [$o1, $o2];
var_dump(in_array($o1, $arr));
var_dump(in_array($o1, $arr, true));
$o3 = new stdClass; $o3->n = 1;
var_dump(in_array($o3, $arr));         // loose: true
var_dump(in_array($o3, $arr, true));   // strict: false

// function_exists / is_callable on closures
$c = function() {};
var_dump(function_exists('strtoupper'));
var_dump(function_exists('zzz_no_func'));
var_dump(is_callable($c));

// Iterator foreach
class MyIter implements Iterator {
    private $i = 0;
    private $data = ['x', 'y', 'z'];
    public function rewind(): void { $this->i = 0; }
    public function valid(): bool { return $this->i < count($this->data); }
    public function current(): mixed { return $this->data[$this->i]; }
    public function key(): mixed { return $this->i; }
    public function next(): void { $this->i++; }
}
foreach (new MyIter as $k => $v) echo "$k=$v\n";
