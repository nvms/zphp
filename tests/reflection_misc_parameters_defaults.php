<?php
// getDefaultProperties lists statics first, isArray/isCallable, getClass on
// builtin types in any case, unset ReflectionClassConstant::$name, readonly
// initialization through a parent's ReflectionProperty, and a method
// implementing an interface in another case isn't listed twice

class P {
    public static $s = 'static';
    public $i = 'instance';
    public readonly string $ro;
}
class K extends P {
    public readonly string $ro;
    public function __tostring(): string { return ''; }
}
function f(array $a, ?callable $c, Array $b, $plain) {}

var_dump((new ReflectionClass('K'))->getDefaultProperties());
foreach ((new ReflectionFunction('f'))->getParameters() as $p) {
    var_dump(@$p->isArray(), @$p->isCallable(), @$p->getClass());
}
$rcc = new ReflectionClassConstant('ReflectionClass', 'IS_FINAL');
unset($rcc->name);
try {
    $rcc->getName();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
$k = (new ReflectionClass('K'))->newInstanceWithoutConstructor();
(new ReflectionProperty('P', 'ro'))->setValue($k, 'set');
var_dump($k->ro);
try {
    (new ReflectionProperty('P', 'ro'))->setValue($k, 'again');
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump(array_map(fn($m) => $m->class . '::' . $m->name, (new ReflectionClass('K'))->getMethods()));
