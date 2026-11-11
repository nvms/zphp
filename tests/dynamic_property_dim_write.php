<?php
// writing an element of a property nothing declares creates the property,
// with the deprecation, however the write is compiled
set_error_handler(function ($no, $str, $file, $line) {
    echo $str, " on line ", $line, "\n";
    return true;
});
class A {}
$a = new A;
$a->p[1] = 2;
$a->q[] = 3;
$a->r['x']['y'] = 1;
$i = 5;
$a->s[$i] = $i;
echo "done\n";
