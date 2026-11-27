<?php
// the first call made with operands waiting on the stack (inside an
// expression, a constructor run from new) costs memory_get_usage() nothing:
// php's VM stack is there before the script runs
function twice($n) { return $n * 2; }
class Box { public function __construct(public int $size) {} }

$before = memory_get_usage();
$total = 1 + twice(2) + strlen(str_repeat('a', 3));
$after = memory_get_usage();
var_dump($total);
var_dump($after - $before);

// what the class keeps from its first instance is not part of this
$warm = new Box(0);
unset($warm);
$before = memory_get_usage();
$list = [twice(1), twice(2), [new Box(twice(1)), new Box(2)]];
unset($list);
var_dump(memory_get_usage() - $before);
