<?php
// headers_sent() fills its by-reference arguments, without warning for an
// undefined variable

$r = headers_sent($file, $line);
$t = new class {
    public int|string $file = 5;
};
headers_sent($t->file);

function f() {
    $r = headers_sent($a);
    return [$r, $a];
}
$f = f();

var_dump($r, $file, $line, $t->file, $f);
