<?php
// a static method called with named arguments gives the parameters they skip
// their defaults

class Defaults
{
    public static function make(string $a, string $b = 'b', bool $c = true, ?bool $d = false, array $e = [1])
    {
        var_dump($b, $c, $d, $e);
    }
}

Defaults::make('a', d: true);
Defaults::make('a', 'x', d: null);
Defaults::make(e: [], a: 'a');
$args = ['c' => false];
Defaults::make('a', ...$args);
