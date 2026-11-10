<?php
// ??= on an uninitialized typed static property initializes it

class Lazy
{
    private static bool $flag;
    private static \Closure $make;
    public static ?int $n;

    public static function flag(): bool { return self::$flag ??= true; }
    public static function make(): string { return (self::$make ??= fn () => "made")(); }
}

var_dump(Lazy::flag(), Lazy::flag(), Lazy::make(), Lazy::$n ??= 3, Lazy::$n);
