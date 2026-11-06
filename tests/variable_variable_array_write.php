<?php
// an element write through ${...}[k] stores into the named variable, making it
// an array when it holds nothing and leaving copies of it alone
$x = "blah";
${$x}["k"] = 1;
${$x}[] = 2;
var_dump($blah);
function f() {
    $x = "q";
    ${$x}["k"] = 2;
    $copy = $q;
    ${$x}["j"] = 3;
    var_dump($q, $copy, isset($$x), isset(${'nope'}), ${'nope'} ?? 'default');
}
f();
