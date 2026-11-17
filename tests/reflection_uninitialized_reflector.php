<?php
// a reflector its constructor never set up has no name yet, and refuses the
// methods that read what it reflects
foreach (['ReflectionClass', 'ReflectionFunction', 'ReflectionMethod', 'ReflectionProperty', 'ReflectionParameter', 'ReflectionClassConstant', 'ReflectionNamedType', 'ReflectionExtension'] as $class) {
    $o = (new ReflectionClass($class))->newInstanceWithoutConstructor();
    var_dump($o);
    foreach (['getName', '__toString', 'isInternal', 'getDocComment', 'allowsNull', 'getVersion'] as $m) {
        if (!method_exists($o, $m)) continue;
        try {
            var_dump($o->$m());
        } catch (Error $e) {
            echo "$class::$m: ", get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
}

class Partial extends ReflectionMethod {
    public function __construct() {}
}
$p = new Partial();
try {
    $p->getName();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
var_dump((new ReflectionFunction('strlen'))->getName(), (new ReflectionMethod('Partial', '__construct'))->class);
