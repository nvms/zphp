<?php
// string offset writes follow zend_assign_to_string_offset, also on a
// global or by-name variable, and `$a[k] = $a` stores the array as it was
$s="abc"; $s[1]="XY"; var_dump($s); $s[5]="q"; var_dump($s); var_dump($s[0]="ZZ"); try { $s[0]=""; } catch (Error $e) { echo $e->getMessage(),"\n"; } $s[-10]="a"; var_dump($s); $s["1x"]="b"; var_dump($s); $s[1.5]="c"; var_dump($s); try { $s["x"]="d"; } catch (TypeError $e) { echo $e->getMessage(),"\n"; }
function h(){ global $s; $s[0]=5; return $s; } var_dump(h(), $s);
$s = "abcdef";
function f() { global $s; $s = "q"; }
f(); var_dump($s);
$t = "abcdef";
function g() { global $t; $t[3] = "X"; var_dump($t); }
g(); var_dump($t);
$u="abc"; $ru=&$u; $ru[1]="Z"; var_dump($u);
$a=[1]; $a[5]=$a; var_dump($a);
$o=new stdClass; $o->p=[1]; $o->p[]=$o->p; var_dump($o->p);
function selfAppendLocal(){ $a=[1]; $a[]=$a; var_dump($a);} selfAppendLocal();
