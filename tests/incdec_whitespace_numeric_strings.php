<?php
// a numeric string with leading or trailing whitespace steps as its number
foreach ([' 5', '5 ', "\t5\n", ' -3 ', ' 1.5', '2.5 ', ' 1e3', ' 9223372036854775807', ' -9223372036854775808', "\r\n7"] as $s) {
    $a = $s; $a++;
    $b = $s; $b--;
    $c = [$s]; $c[0]++;
    $o = new stdClass; $o->p = $s; $o->p--;
    var_dump($a, $b, $c[0], $o->p);
}
