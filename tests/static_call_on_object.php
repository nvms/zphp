<?php

class Counter {
    private static int $count = 0;

    public static function increment(): void {
        self::$count++;
    }

    public static function getCount(): int {
        return self::$count;
    }

    public static function reset(): void {
        self::$count = 0;
    }
}

// $obj::staticMethod() syntax
$obj = new Counter();
$obj::increment();
$obj::increment();
echo $obj::getCount() . "\n";

// string class name dynamic call
$class = 'Counter';
$class::reset();
$class::increment();
echo $class::getCount() . "\n";

// with arguments
class Math {
    public static function add(int $a, int $b): int {
        return $a + $b;
    }
}

$m = new Math();
echo $m::add(3, 4) . "\n";
