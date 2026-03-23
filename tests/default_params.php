<?php
function greet($name = "World") {
    return "Hello " . $name;
}
echo greet() . "\n";
echo greet("PHP") . "\n";

function add($a, $b = 10) {
    return $a + $b;
}
echo add(5) . "\n";
echo add(5, 20) . "\n";

function flags($a, $b = true, $c = null) {
    $out = $a;
    if ($b) $out .= " flagged";
    if ($c !== null) $out .= " " . $c;
    return $out;
}
echo flags("test") . "\n";
echo flags("test", false) . "\n";
echo flags("test", true, "extra") . "\n";

function defaults_with_types(int $x = 5, string $s = "hi"): string {
    return $s . " " . $x;
}
echo defaults_with_types() . "\n";
echo defaults_with_types(10) . "\n";
echo defaults_with_types(10, "bye") . "\n";
