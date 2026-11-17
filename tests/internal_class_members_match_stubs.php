<?php
// internal classes list the methods and properties php's stubs declare
function own_methods(string $class): string {
    $own = [];
    foreach ((new ReflectionClass($class))->getMethods() as $m) {
        if ($m->class === $class) $own[] = $m->name;
    }
    return implode(',', $own);
}
function props(string $class): string {
    $p = [];
    foreach ((new ReflectionClass($class))->getProperties() as $pr) {
        $p[] = $pr->class . '::' . ($pr->hasType() ? $pr->getType() . ' ' : '') . $pr->name;
    }
    return implode(',', $p);
}
foreach (['Exception', 'Error', 'ArrayObject', 'ArrayIterator', 'ReflectionClass', 'ReflectionProperty', 'ReflectionType', 'ReflectionParameter'] as $c) {
    echo $c, ": ", own_methods($c), "\n  ", props($c), "\n";
}
echo props('ReflectionMethod'), "\n", props('ReflectionObject'), "\n", props('ReflectionEnumBackedCase'), "\n";

var_dump(in_array('__get', get_class_methods('ArrayObject')));
var_dump(method_exists('ArrayObject', '__isset'), method_exists('ArrayIterator', '__set'));
var_dump(method_exists('Exception', '__clone'), method_exists('Error', '__wakeup'));
var_dump(is_callable([new ArrayObject([]), '__get']));
var_dump((new ReflectionClass('ArrayObject'))->hasMethod('__unset'));
try {
    (new ReflectionClass('ArrayIterator'))->getMethod('__get');
} catch (ReflectionException $e) {
    echo $e->getMessage(), "\n";
}
var_dump((new ReflectionClass('Closure'))->hasMethod('__invoke'));

echo new ReflectionMethod('Exception', '__clone');
echo new ReflectionMethod('Error', '__wakeup');
echo new ReflectionMethod('ReflectionProperty', '__clone');
echo new ReflectionMethod('ReflectionClass', '__toString');

class MyException extends Exception {
    public function __clone(): void {}
}
foreach ([new Exception, new MyException, new ReflectionClass('stdClass')] as $o) {
    try {
        $x = clone $o;
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
try {
    (new Exception)->__clone();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

// __wakeup drops a message or code of the wrong type
$e = unserialize('O:9:"Exception":2:{s:10:"' . "\0*\0" . 'message";i:1;s:7:"' . "\0*\0" . 'code";s:1:"x";}');
var_dump($e->getMessage(), $e->getCode());
$e = unserialize('O:5:"Error":2:{s:10:"' . "\0*\0" . 'message";s:2:"ok";s:7:"' . "\0*\0" . 'code";i:7;}');
var_dump($e->getMessage(), $e->getCode());
$e = new Exception("kept", 3);
$e->__wakeup();
var_dump($e->getMessage(), $e->getCode());
