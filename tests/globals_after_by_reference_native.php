<?php
// a native writing a global variable through a by-reference argument
// updates $GLOBALS too

$out = new stdClass;
$out->x = $out;
parse_str("a=b&c[]=d", $out);
var_dump($GLOBALS['out']);
var_dump(gc_collect_cycles());

$arr = [3, 1, 2];
sort($arr);
var_dump($GLOBALS['arr']);

preg_match('/(b)(c)/', 'abcd', $m);
var_dump($GLOBALS['m']);

$s = 'x';
settype($s, 'integer');
var_dump($GLOBALS['s']);

$list = ['b' => 1, 'a' => 2];
ksort($list);
foreach ($GLOBALS['list'] as $k => $v) echo "$k=$v\n";
