<?php
declare(strict_types=1);

function f(int $a, $b) { return $a; }

try {
    f("3", ?);
} catch (\TypeError $e) {
    echo $e::class, ": ", $e->getMessage(), "\n";
}

function make() {
    try {
        f("3", ?);
    } catch (\TypeError $e) {
        echo $e::class, ": ", $e->getMessage(), "\n";
    }
}
make();
?>
