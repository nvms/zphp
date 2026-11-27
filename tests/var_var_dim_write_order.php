<?php
// ${...}[k] = v fetches the variable after the key and the value ran, so a
// key or value that changes the name writes where the name then points
function one() {
    $n = 'a';
    $$n[++$n] = 'x';
    var_dump(get_defined_vars());
}
function two() {
    $n = 'a';
    $$n[0] = $n = 'b';
    var_dump(get_defined_vars());
}
function three() {
    $n = 'a';
    $k = 'key';
    $$n[$k] = ($n = 'c') . ($k = 'late');
    var_dump(get_defined_vars());
}
function four() {
    $n = 'a';
    $$n .= $$n[++$n] = 'test';
    var_dump(get_defined_vars());
}
one();
two();
three();
@four();
