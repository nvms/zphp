<?php
// the reflection constructors and methods check their arguments as php's
// zend_parse_parameters does, and invoke/newInstance bind arguments (named
// ones included) as a call from internal code

function show(callable $f) {
    try {
        $r = $f();
        echo is_object($r) ? get_class($r) : var_export($r, true), "\n";
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

interface I {}
abstract class Abs { abstract function a(); }
class Two implements I {
    function __construct($a, $b = 'b') { echo "Two($a, $b) ", count(func_get_args()), "\n"; }
    private function secret($x) { return "secret $x"; }
    static function stat(...$r) { return static::class . ' ' . implode(',', $r); }
}
class Sub extends Two {}
class PrivateCtor { private function __construct() {} }
class NoCtor {}
enum Suit: string { case Hearts = 'H'; const X = 1; }
enum Pure { case One; }

show(fn() => new ReflectionClass([]));
show(fn() => new ReflectionClass('Nope'));
show(fn() => new ReflectionObject('Two'));
show(fn() => (new ReflectionObject(new Sub(1)))->name);
show(fn() => new ReflectionMethod([], 'x'));
show(fn() => new ReflectionMethod('Two', []));
show(fn() => new ReflectionMethod(new Two(1), null));
show(fn() => ReflectionMethod::createFromMethodName('Two'));
show(fn() => ReflectionMethod::createFromMethodName('Nope::x'));
show(fn() => ReflectionMethod::createFromMethodName('Two::nope'));
show(fn() => new ReflectionFunction([]));
show(fn() => new ReflectionFunction('nope'));
show(fn() => new ReflectionParameter('nope', 0));
show(fn() => new ReflectionParameter(['Two', 'nope'], 0));
show(fn() => new ReflectionParameter(['Two'], 0));
show(fn() => new ReflectionParameter(5, 0));
show(fn() => new ReflectionParameter(['Two', '__construct'], 'c'));
show(fn() => new ReflectionParameter(['Two', '__construct'], 5));
show(fn() => new ReflectionParameter(['Two', '__construct'], -1));
show(fn() => (new ReflectionParameter(['Sub', '__construct'], 'b'))->getPosition());
show(fn() => new ReflectionClassConstant('Nope', 'X'));
show(fn() => new ReflectionClassConstant('Two', 'X'));
show(fn() => new ReflectionEnum('Two'));
show(fn() => new ReflectionEnumUnitCase('Suit', 'X'));
show(fn() => new ReflectionEnumBackedCase('Pure', 'One'));
show(fn() => new ReflectionExtension('nope'));
show(fn() => (new ReflectionExtension('spl'))->getName());

$c = new ReflectionClass('Sub');
show(fn() => $c->getMethod([]));
show(fn() => $c->isSubclassOf('Nope'));
show(fn() => $c->isSubclassOf(new ReflectionClass('Two')));
show(fn() => $c->isSubclassOf('Sub'));
show(fn() => $c->implementsInterface('Two'));
show(fn() => $c->implementsInterface('Nope'));
show(fn() => $c->implementsInterface('I'));
show(fn() => $c->getStaticPropertyValue('nope'));
show(fn() => $c->getStaticPropertyValue('nope', 'default'));
show(fn() => $c->setStaticPropertyValue('nope', 1));

show(fn() => $c->newInstance(1, 2));
show(fn() => $c->newInstanceArgs(['b' => 2, 'a' => 1]));
show(fn() => $c->newInstanceArgs(['b' => 2]));
show(fn() => $c->newInstanceArgs(['c' => 2]));
show(fn() => $c->newInstanceArgs([1, 'a' => 2]));
show(fn() => $c->newInstanceArgs(['a' => 1, 2]));
show(fn() => $c->newInstanceArgs('x'));
show(fn() => (new ReflectionClass('PrivateCtor'))->newInstance());
show(fn() => (new ReflectionClass('NoCtor'))->newInstance(1));
show(fn() => (new ReflectionClass('NoCtor'))->newInstanceArgs([]));
show(fn() => (new ReflectionClass('Abs'))->newInstance());
show(fn() => (new ReflectionClass('I'))->newInstanceWithoutConstructor());
show(fn() => (new ReflectionClass('Generator'))->newInstanceWithoutConstructor());

$secret = new ReflectionMethod('Two', 'secret');
$two = new Two(0);
show(fn() => $secret->invoke($two, 'x'));
show(fn() => $secret->invokeArgs($two, ['x' => 'named']));
show(fn() => $secret->invoke(true));
show(fn() => $secret->invoke(null));
show(fn() => $secret->invoke(new NoCtor));
show(fn() => $secret->invokeArgs($two, true));
show(fn() => (new ReflectionMethod('Abs', 'a'))->invoke(null));
show(fn() => (new ReflectionMethod('Sub', 'stat'))->invoke(null, 1, 2));
show(fn() => (new ReflectionMethod('Sub', 'stat'))->invokeArgs(new NoCtor, [3]));
function f($x, $y = 5) { return "$x $y"; }
show(fn() => (new ReflectionFunction('f'))->invokeArgs(['x' => 1]));
show(fn() => (new ReflectionFunction('f'))->invokeArgs(['y' => 1]));
