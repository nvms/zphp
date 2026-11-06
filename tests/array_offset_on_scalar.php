<?php
// reading an element of a scalar warns and reads null; destructuring a
// scalar warns differently, except null, which destructures quietly
$n = null; $i = 5; $b = true; $f = 1.5;
var_dump($n[0], $i["x"], $b[1], $f[0], $n[0][1]);
$r = fopen('php://memory', 'r');
var_dump($r[0]);
function g() { return null; }
var_dump(g()[0]);
var_dump(isset($n[0]), $n[0] ?? "d", empty($i[0]), @$n[0]);
foreach ([null, false, 1, 1.5, "ab", $r] as $v) {
    [$a, $c] = $v;
    ['k' => $d] = $v;
    var_dump($a, $d);
}
[[$x]] = [null];
[[$y]] = [3];
foreach ([1, null, "s"] as [$p]) var_dump($p);
$o = new stdClass;
try { var_dump($o[0]); } catch (Error $e) { echo $e->getMessage(), "\n"; }
try { [$z] = $o; } catch (Error $e) { echo $e->getMessage(), "\n"; }
$rows = [[1, 2], null, 5];
for ($k = 0; $k < 3; $k++) { $row = $rows[$k]; echo $row[0] ?? 'n', $row[1], "\n"; }
for ($k = 0; $k < 3; $k++) { [$p, $q] = $rows[$k]; var_dump($p); }
$str = "abc";
for ($k = 0; $k < 2; $k++) { [$ch] = $str; var_dump($ch, $str[0]); }
