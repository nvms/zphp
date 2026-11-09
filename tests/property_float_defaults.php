<?php
// an int default of a float property is a float, as php converts it
class Defaults {
    const SIX = 6;
    public float $plain = 2;
    public static float $static = 3;
    public ?float $nullable = 4;
    public float|string $union = 5;
    public float $fromConstant = self::SIX;
    public int|float $either = 7;
}
var_dump(new Defaults, Defaults::$static);
