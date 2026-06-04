<?php

// foreach-by-ref binds $v as a TRUE reference to each element (not a value copy
// written back at end of iteration). so capturing `$x = &$v` / `$arr[] = &$v`
// aliases the element's own storage, writes propagate live, and an element is
// left is_ref after the loop only when something else still references it.

// 1. plain by-ref write
$a = [1, 2, 3];
foreach ($a as &$v) { $v *= 10; }
unset($v);
echo "1: ", json_encode($a), "\n";                 // [10,20,30]

// 2. by-ref with key
$b = ['x' => 1, 'y' => 2];
foreach ($b as $k => &$v) { $v = $k . $v; }
unset($v);
echo "2: ", json_encode($b), "\n";                 // {"x":"x1","y":"y2"}

// 3. capture &$v into another array - each $refs[$k] aliases $a[$k]
$c = [1, 2, 3];
$r = [];
foreach ($c as $k => &$v) { $r[$k] = &$v; }
unset($v);
$r[1] = 99;
echo "3: ", json_encode($c), "\n";                 // [1,99,3]

// 4. unset mid-iteration must not resurrect
$d = [1, 2, 3, 4];
foreach ($d as $k => &$v) {
    if ($k == 1) { unset($d[1]); } else { $v += 100; }
}
unset($v);
echo "4: ", json_encode($d), "\n";                 // {"0":101,"2":103,"3":104}

// 5. nested by-ref foreach
$m = [[1, 2], [3, 4]];
foreach ($m as &$row) { foreach ($row as &$x) { $x *= 2; } unset($x); }
unset($row);
echo "5: ", json_encode($m), "\n";                 // [[2,4],[6,8]]

// 6. COW: by-ref over a copy must not corrupt the original
$e = [1, 2, 3];
$copy = $e;
foreach ($e as &$v) { $v = 0; }
unset($v);
echo "6: ", json_encode($e), " orig=", json_encode($copy), "\n"; // [0,0,0] orig=[1,2,3]

// 7. capture-before-unset (write through the captured ref while still in scope)
$g = [10, 20];
$caps = [];
foreach ($g as $k => &$v) { $caps[] = &$v; }
$caps[0] = 111;
echo "7: ", json_encode($g), "\n";                 // [111,20]

// 8. the post-loop is_ref gotcha: an UNCAPTURED by-ref loop must leave the array
// as plain values, so a later copy is independent
$h = [1, 2, 3];
foreach ($h as &$v) {}
unset($v);
$hb = $h;
$hb[0] = 99;
echo "8: ", json_encode($h), "\n";                 // [1,2,3]  (not shared)

// 9. nested capture: $caps["$i$j"] aliases $m[$i][$j]
$mm = [[1, 2], [3, 4]];
$cap2 = [];
foreach ($mm as $i => &$row) {
    foreach ($row as $j => &$cc) { $cap2["$i$j"] = &$cc; }
}
unset($row, $cc);
$cap2['11'] = 88;
echo "9: ", json_encode($mm), "\n";                // [[1,2],[3,88]]

// 10. object-property iterable by-ref
class Bag { public array $items = [10, 20, 30]; }
$bag = new Bag();
foreach ($bag->items as &$x) { $x++; }
unset($x);
echo "10: ", json_encode($bag->items), "\n";       // [11,21,31]

// 11. unset a FUTURE key during by-ref iteration: reaching the deleted key must
// not resurrect it (a write to $v on a deleted key writes a detached ref)
$u = [1, 2, 3, 4, 5];
foreach ($u as $k => &$v) {
    if ($k === 1) { unset($u[1], $u[3]); } else { $v *= 10; }
}
unset($v);
echo "11: ", json_encode($u), "\n";                // {"0":10,"2":30,"4":50}
