<?php
// a restored interval's f becomes whole microseconds through
// zend_dval_to_lval, which warns for a value an int can't hold

$payload = 'O:12:"DateInterval":9:{s:1:"y";i:1;s:1:"m";i:0;s:1:"d";i:4;s:1:"h";i:0;s:1:"i";i:0;s:1:"s";i:0;s:1:"f";i:9999999999990;s:6:"invert";i:0;s:4:"days";b:0;}';
$i = unserialize($payload);
var_dump($i->y, $i->d, is_float($i->f));
$j = DateInterval::__set_state(["f" => 1.5e300, "y" => 0]);
var_dump($j->y, is_float($j->f));
$k = DateInterval::__set_state(["f" => 0.25]);
var_dump($k->f);
