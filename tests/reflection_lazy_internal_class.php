<?php
// setRawValueWithoutLazyInitialization() and skipLazyInitialization() refuse
// an object of an internal class with its own property handlers
function test(object $obj, string $class, string $prop) {
    $r = new ReflectionProperty($class, $prop);
    try {
        $r->setRawValueWithoutLazyInitialization($obj, 'x');
        echo "set\n";
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
    try {
        $r->skipLazyInitialization($obj);
        echo "skipped\n";
    } catch (ReflectionException $e) {
        echo $e->getMessage(), "\n";
    }
}
test(new ReflectionClass('stdClass'), 'ReflectionClass', 'name');
test(new ReflectionMethod('ReflectionClass', 'getName'), 'ReflectionMethod', 'class');
class Plain { public $p; }
test(new Plain, 'Plain', 'p');
test(new Exception('m'), 'Exception', 'message');
