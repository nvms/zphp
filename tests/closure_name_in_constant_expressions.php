<?php
// a closure in a constant expression is named after where it is written:
// the file for a property default or a class constant, the method or
// function for a parameter default or an attribute argument

#[Attribute(Attribute::TARGET_ALL)]
class Holder {
    public function __construct(public Closure $closure) {}
}

class Box {
    const MAKER = static function () { return 'const'; };
    public Closure $instance = static function () { return 'instance'; };
    public static Closure $shared = static function () { return 'static'; };

    #[Holder(static function () { return 'method attribute'; })]
    public function run($callback = static function () { return 'method default'; }) {
        return $callback;
    }
}

#[Holder(static function () { return 'function attribute'; })]
function work($callback = static function () { return 'function default'; }) {
    return $callback;
}

$closures = [
    Box::MAKER,
    (new Box)->instance,
    Box::$shared,
    (new Box)->run(),
    work(),
    (new ReflectionMethod('Box', 'run'))->getAttributes()[0]->newInstance()->closure,
    (new ReflectionFunction('work'))->getAttributes()[0]->newInstance()->closure,
];
foreach ($closures as $closure) {
    $name = (new ReflectionFunction($closure))->getName();
    echo str_replace(__FILE__, 'FILE', $name), ' => ', $closure(), "\n";
}

// the name shows in a trace too
class Secret { public function __construct(private string $value) {} }
class Reader {
    public Closure $read = static function (Secret $s) { return $s->value; };
}
try {
    ((new Reader)->read)(new Secret('x'));
} catch (Error $e) {
    echo $e->getMessage(), "\n";
    echo str_replace(__FILE__, 'FILE', $e->getTrace()[0]['function']), "\n";
}
