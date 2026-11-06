<?php
// a variable read in a loop before the statement that first writes it reads
// what that write stored on the previous pass
function counter() {
    $n = 0;
    while ($n < 3) {
        $n++;
        @$i++;
        @$s .= 'x';
    }
    var_dump($i, $s);
}
counter();
function firstPass() {
    while (true) {
        var_dump($a + 1);
        $a = 1;
        if (@$i++) break;
    }
}
firstPass();
