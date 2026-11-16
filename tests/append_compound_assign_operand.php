<?php
// `$a[] op= v` as the operand of a prefix operator parses as the assignment

$a = [];
@$a[] .= "x";
$r = @$a[] .= "y";
var_dump($a, $r);

$b = [];
@$b[] += 5;
var_dump(!$b[] -= 1, $b);

$c = ["k" => []];
@$c["k"][] .= "z";
var_dump($c);

class P { public $list = []; }
$p = new P;
@$p->list[] .= "w";
var_dump($p->list);
