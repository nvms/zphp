<?php
// the matches variable gets a new array: copies of the old one keep it
preg_match("/(a)/", "a", $m);
$copy = $m;
preg_match("/(b)/", "b", $m);
var_dump($copy[1], $m[1]);
preg_match_all("/(a)/", "a", $n);
$c2 = $n;
preg_match_all("/(b)/", "b", $n);
var_dump($c2[1][0], $n[1][0]);
$q = ["x"];
$c3 = $q;
preg_match("/(z)/", "y", $q);
var_dump($c3, $q);
// an empty subject, matched by a cached pattern
for ($i = 0; $i < 3; $i++) var_dump(preg_match('/^(\.((?:[^\\\\.\[]|\\\\.)++)|\[([^\]]++)\])(.*)/', ''));
foreach (new RegexIterator(new ArrayIterator(["apple", "berry"]), '/(\w+)y$/', RegexIterator::GET_MATCH) as $mm) echo $mm[1], "\n";
