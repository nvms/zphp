<?php
// a compound assignment evaluates its right side first and reads the target
// as the operator runs, so a right side that changes the target is seen;
// calls inside the target still run before the right side
function k() { echo "k "; return 'k'; }
function bump(&$r) { $r = 100; echo "bump "; return 1; }
class Box { public $v = 1; public $arr = ['k' => 1]; }
$b = new Box;
$a = ['k' => 1, 'n' => ['k' => 1]];
$a['k'] += bump($a['k']); echo $a['k'], "\n";
$a['n']['k'] *= bump($a['n']['k']); echo $a['n']['k'], "\n";
$a[k()] -= bump($a['k']); echo $a['k'], "\n";
$b->v .= bump($b->v); echo $b->v, "\n";
$b->arr['k'] += bump($b->arr['k']); echo $b->arr['k'], "\n";
$name = 'v'; $b->$name += bump($b->v); echo $b->v, "\n";
$vv = 'x'; $x = 1; $$vv += bump($x); echo $x, "\n";
$x = 1; function h() { global $x; $x = 10; return 1; } $x += h(); echo $x, "\n";
$x = 'a'; $x .= ($x = 'b'); echo $x, "\n";
$i = 1; $i += $i++; echo $i, "\n";
$arr = [1, 2]; $arr[0] += array_push($arr, 3); print_r($arr);
$o = new stdClass; $o->$undefined_name .= h();
