<?php

function f($a, #[SensitiveParameter] $b, $c) {
    g();
}

function g() {
    throw new Exception();
}

$f = f(?, ?, 3);
$f(1, 2);

?>
