<?php
// php compiles $a > $b as $b < $a: a pair that compares as 1 both ways
// (uncomparable) is neither greater nor smaller

$a = ["x" => 1];
$b = ["y" => 1];
var_dump($a > $b, $b > $a, $a < $b, $b < $a, $a >= $b, $a <= $b, $a == $b);
var_dump([1, 2] > [1], [1] > [1, 2], [2] >= [1], [1] >= [1]);

$z1 = new DateTimeZone("+02:00");
$z2 = new DateTimeZone("-02:00");
var_dump($z1 > $z2, $z2 > $z1, $z1 >= $z2, $z1 == $z2);

$o1 = new stdClass;
$o1->a = 1;
$o2 = new ArrayObject();
var_dump($o1 > $o2, $o2 > $o1);

var_dump(2 > 1, "b" > "a", null > false, "10" > "9", "abc" >= "abd");
