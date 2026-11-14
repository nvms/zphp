<?php
// the global symbol table lists what the cli registers first, then the
// script's variables in the order they appear; $GLOBALS is not one of them
$first = 1;
$second = [2];
echo implode(",", array_keys(get_defined_vars())), "\n";

$key = 'asdf';
foreach (get_defined_vars() as $key => $value) {
    if ($key[0] !== '_' && $key !== 'argv' && $key !== 'argc') unset($$key);
}
var_dump(isset($key), isset($first), isset($second));
echo implode(",", array_keys(get_defined_vars())), "\n";

function inner($a)
{
    $b = 2;
    return array_keys(get_defined_vars());
}
echo implode(",", inner(1)), "\n";
