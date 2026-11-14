<?php
// reflection writing a static property that is a reference held by a typed
// property follows that type

class Test {
    public static $x;
    public static int $y = 2;
}

$rc = new ReflectionClass('Test');
try {
    $rc->setStaticPropertyValue('y', 'foo');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$rc->setStaticPropertyValue('y', '21');
var_dump(Test::$y);

Test::$x = &Test::$y;
try {
    $rc->setStaticPropertyValue('x', 'foo');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(Test::$y);
$rc->setStaticPropertyValue('x', '42');
var_dump(Test::$x, Test::$y);

$rp = new ReflectionProperty('Test', 'x');
try {
    $rp->setValue(null, []);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$rp->setValue(null, 7.0);
var_dump(Test::$y);
