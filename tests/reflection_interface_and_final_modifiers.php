<?php
// interface methods are public abstract, an abstract class lists the
// interface methods it inherits, and a static property can be final
class T { function foo() {} function __construct() {} }
class D extends T {}
foreach ((new ReflectionClass('D'))->getMethods() as $m) echo $m->class, '::', $m->name, "\n";
echo (new ReflectionMethod('D', 'foo'))->class, "\n";
interface I { public function int(); }
abstract class AC implements I { abstract function x(); }
foreach ((new ReflectionClass('I'))->getMethods() as $m) printf("%s %x\n", $m->name, $m->getModifiers());
foreach ((new ReflectionClass('AC'))->getMethods() as $m) printf("%s::%s %x\n", $m->class, $m->name, $m->getModifiers());
class P { public static final $a8; public final $a7; }
printf("%d %d\n", (new ReflectionProperty('P', 'a8'))->getModifiers(), (new ReflectionProperty('P', 'a7'))->getModifiers());
