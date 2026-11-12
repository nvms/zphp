<?php
class Plain {}
class Text { function __toString(): string { return "abc"; } }
$o = new Plain;
$s = new Text;
$n = null;
$t = true;
$f = false;
var_dump($o == true, $o == $t, true == $o, $o == false, $o != $t, $f == $o);
var_dump($o > $n, $o < $n, $n < $o, $o == $n, $o >= $n);
var_dump($o > $f, $o >= true, $o < true, $f < $o);
var_dump($s == "abc", $s > "abb", $s < "abd", $o == "abc", $o > "abc");
var_dump($o == 1, $o > 0, $o == 1.0, $o > [1], $o == []);
var_dump([$o] == [true], [$o] > [false], [$o] == [null]);
