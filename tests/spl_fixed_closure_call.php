<?php
// SplFixedArray basic
$a = new SplFixedArray(5);
$a[0] = 'x'; $a[1] = 'y'; $a[4] = 'z';
echo count($a), "\n";
echo $a[0], "\n";
var_dump($a[2]);
echo $a[4], "\n";

// out of bounds throws RuntimeException
try {
    $a[10] = 'oops';
} catch (\RuntimeException $e) {
    echo "set-oob: caught\n";
}

try {
    $x = $a[10];
} catch (\RuntimeException $e) {
    echo "get-oob: caught\n";
}

// negative throws
try {
    $a[-1] = 'no';
} catch (\RuntimeException $e) {
    echo "neg: caught\n";
}

// foreach
foreach ($a as $i => $v) echo "$i:", $v ?? 'null', " ";
echo "\n";

// fromArray / toArray
$f = SplFixedArray::fromArray([1, 2, 3, 4, 5]);
echo count($f), "\n";
print_r($f->toArray());

// setSize
$f->setSize(3);
echo count($f), "\n";

// Closure::call
class Box {
    private $v = 'private!';
}
$reader = function() { return $this->v; };
echo $reader->call(new Box), "\n";

// call with args
$add = function($x) { return $this->v + $x; };
class N { private $v = 10; }
echo $add->call(new N, 5), "\n";

// bindTo
$bound = $reader->bindTo(new Box, Box::class);
echo $bound(), "\n";

// Closure::bind static
$h = function() { return self::$x; };
class S { public static $x = 'sv'; }
$h2 = Closure::bind($h, null, S::class);
echo $h2(), "\n";

