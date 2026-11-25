<?php

function f($a, #[SensitiveParameter] $b, $c, #[SensitiveParameter] ...$d) {
    throw new Exception();
}

$f = f(1, ?, ?, ?, ...)('normal param', 3, 'reified variadic', 'variadic');

?>
