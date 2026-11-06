<?php
// a match that fails on malformed utf-8, a bad offset or an exhausted limit
// reports it through each function's failure value and preg_last_error
$bad = "a\xff";
var_dump(preg_match('//u', $bad), preg_last_error(), preg_match('//u', "ok"), preg_last_error());
var_dump(preg_match_all('/a/u', $bad), preg_last_error());
var_dump(preg_replace('/a/u', 'b', $bad), preg_last_error());
var_dump(preg_replace('/a/u', 'b', ["x" => $bad, "y" => "a"]));
var_dump(preg_split('/a/u', $bad), preg_last_error());
var_dump(preg_replace_callback('/a/u', fn($m) => 'b', $bad), preg_last_error());
var_dump(preg_grep('/a/u', [$bad, "a"]), preg_grep('/a/u', ["a", $bad]), preg_last_error());
$s = "héllo wörld";
var_dump(preg_match('/ö/u', $s, $m, 0, 2), preg_last_error_msg());
var_dump(preg_match('/l/u', $s, $m, 0, 1), $m);
$t = "abc";
var_dump(preg_match('/c/u', $t));
$t .= "\xff";
var_dump(preg_match('/c/u', $t), preg_last_error_msg());
var_dump(preg_match('/(?:\D+|<\d+>)*[!?]/', 'foobar foobar foobar'), preg_last_error_msg());
ini_set('pcre.backtrack_limit', '10');
var_dump(preg_match('/a+b/', str_repeat('a', 20)), preg_last_error_msg());
// a long valid subject matched at every offset
$long = str_repeat('é', 50000);
$pos = 0;
$n = 0;
while (preg_match('/\G./u', $long, $m, 0, $pos)) { $pos += strlen($m[0]); $n++; }
var_dump($n);
