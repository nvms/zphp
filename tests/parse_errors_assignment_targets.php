<?php
// php's grammar assigns only to variables and references only variables

class A { const B = 1; public static $p = 1; }
function &r() { static $v = 0; return $v; }

$codes = [
    'A::B = 2;',
    '$a = &A::B;',
    'FOO = 1;',
    '1 = 2;',
    '"s" .= "t";',
    '$x = &1;',
    '$x = &"str";',
    'A::$p = 5; echo A::$p, "\n";',
    '$x = &A::$p; $x = 6; echo A::$p, "\n";',
    '$y = &r(); $y = 7; echo r(), "\n";',
    '[$m, $n] = [1, 2]; echo $m + $n, "\n";',
    'list($m) = [3]; echo $m, "\n";',
    '$o = new stdClass; $o->p = 1; $o->q ??= 2; echo $o->q, "\n";',
    '$arr = []; $arr[] = 1; $arr[0] += 4; echo $arr[0], "\n";',
];
foreach ($codes as $code) {
    try {
        eval($code);
    } catch (ParseError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
