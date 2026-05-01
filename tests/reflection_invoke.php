<?php

class Calc {
    public int $base;
    public function __construct(int $base = 0) { $this->base = $base; }
    public function add(int $n): int { return $this->base + $n; }
    public static function mul(int $a, int $b): int { return $a * $b; }
    public static function factory(int $start): self { return new self($start); }
}

$rc = new ReflectionClass(Calc::class);
$obj = new Calc(10);

// instance method via invoke
$add = $rc->getMethod('add');
echo $add->invoke($obj, 5) . "\n";
echo $add->invokeArgs($obj, [7]) . "\n";

// static method via invoke (null target)
$mul = $rc->getMethod('mul');
echo $mul->invoke(null, 3, 4) . "\n";
echo $mul->invokeArgs(null, [6, 7]) . "\n";

// static factory
$factory = $rc->getMethod('factory');
$o = $factory->invoke(null, 100);
echo $o::class . " base=" . $o->base . "\n";

// invokeArgs with empty array on instance
$rc2 = new ReflectionClass(DateTime::class);
$f = $rc2->getMethod('format');
$d = new DateTime('2024-01-15');
echo $f->invokeArgs($d, ['Y-m-d']) . "\n";
