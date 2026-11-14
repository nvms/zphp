<?php
// a float against a non-numeric string compares as the float's text, which
// follows the precision ini
var_dump(INF == "INF", -INF == "-INF", NAN == "NAN", "INF" == INF);
var_dump(INF <=> "INF", "INF" <=> INF, -INF <=> "-INF", NAN <=> "NAN", "NAN" <=> NAN);
var_dump(1.5 == "1.5x", 1.5 <=> "1.5x", 1.5 <=> "abc", 2.0 <=> "2x", 1e100 <=> "1.0E+100x");
var_dump(1.75 < "1.75abc", 1.75 > "1.75abc");
ini_set('precision', '3');
var_dump(1.23456 == "1.23x", 1.23456 <=> "1.23");
