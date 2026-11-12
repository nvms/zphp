<?php
// extract(EXTR_REFS) binds each variable to the array element, which php
// passes by reference when it can (ZEND_ARG_SEND_PREFER_REF) and as a value
// otherwise
$arr=["foo"=>"aaa"]; $copy=$arr;
extract($arr, EXTR_REFS);
$foo="bbb"; var_dump($arr, $copy, $foo);
function f(){ $a=["x"=>1]; extract($a, EXTR_REFS|EXTR_PREFIX_ALL, "p"); $p_x=5; var_dump($a); }
f();
var_dump(extract(["q"=>1], EXTR_REFS), $q);
function g(){return ["r"=>2];} var_dump(extract(g())); var_dump($r);
try { extract($undef); } catch (TypeError $e) { echo $e->getMessage(), "\n"; }
