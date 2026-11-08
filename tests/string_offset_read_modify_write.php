<?php
// an assignment operator or increment on a string offset is php's Error
$s = "ab";
foreach ([fn() => $s[0] .= "z", fn() => $s[0]++, fn() => $s[5] .= "z", fn() => $s[0] ??= "q", fn() => [$s[0], 1]] as $f) { try { var_dump($f()); } catch (Error $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; } }

$s = "ab";
try { $s[0]++; } catch (Error $e) { echo $e->getMessage(), "\n"; }
$f = fn() => $s[0]++;
try { var_dump($f()); } catch (Error $e) { echo $e->getMessage(), "\n"; }
function g() { $t = "ab"; return $t[0]++; }
try { var_dump(g()); } catch (Error $e) { echo $e->getMessage(), "\n"; }
