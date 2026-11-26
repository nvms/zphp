<?php
// a ReflectionProperty evaluates nothing when made: a default naming a
// constant is evaluated when the default is asked for (or the class used)
class C {
    public stdClass $a = FOO;
    public $c = [1, 2];
    public int $d;
}
$ra = new ReflectionProperty(C::class, 'a');
$rc = new ReflectionProperty(C::class, 'c');
$rd = new ReflectionProperty(C::class, 'd');
$all = (new ReflectionClass('C'))->getProperties();
echo "constructed\n";
var_dump($ra->hasDefaultValue(), $rd->hasDefaultValue(), count($all));
try {
    var_dump($ra->getDefaultValue());
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
define('FOO', new stdClass);
var_dump($ra->getDefaultValue());
$v = $rc->getDefaultValue();
$v[] = 3;
var_dump($rc->getDefaultValue(), $v);
new C;
echo $ra, $rc;

class D {
    public $x = UNDEFINED_ONE;
}
$rx = (new ReflectionClass('D'))->getProperty('x');
echo "made\n";
try {
    $rx->getDefaultValue();
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}

class E {
    public stdClass $a = BAZ;
}
$re = new ReflectionProperty(E::class, 'a');
define('BAZ', new stdClass);
new E;
echo $re;
