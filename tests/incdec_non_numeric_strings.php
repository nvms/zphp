<?php
// ++ and -- on a string that is not numeric: php's deprecations, which an
// error handler sees and can turn into exceptions, and -- leaves it as it is
set_error_handler(function($n, $m) { echo "handler($n): $m\n"; return true; });
foreach (['199Z', 'x', '', ' ', 'A199', 'Hello world', '🐘', '5', ' 5', '5 ', '1e3', 'zz', 'Zz', 'a9'] as $value) {
    $copy = $value;
    $value++;
    var_dump($value);
    $value--;
    var_dump($value);
    $w = $copy;
    var_dump($w--, $w, --$w, $w++, ++$w);
    $a = [$copy, 'k' => $copy];
    $a[0]++; $a['k']--;
    $p = $a[0]--; $q = $a['k']++;
    var_dump($a, $p, $q);
    $o = new stdClass; $o->p = $copy;
    $o->p--; $o->p++;
    var_dump($o->p, $copy);
}
function f() { static $s = 'a'; $s--; $s++; return $s; }
var_dump(f(), f());
set_error_handler(function($n, $m) { throw new Exception($m); });
foreach (['abc', '', 'x y'] as $v) {
    try { $v++; } catch (Exception $e) { echo $e->getMessage(), "\n"; }
    var_dump($v);
    try { $v--; } catch (Exception $e) { echo $e->getMessage(), "\n"; }
    var_dump($v);
    $arr = [$v];
    try { $arr[0]--; } catch (Exception $e) { echo $e->getMessage(), "\n"; }
    try { $r = $arr[0]++; } catch (Exception $e) { echo $e->getMessage(), "\n"; }
    var_dump($arr);
}
