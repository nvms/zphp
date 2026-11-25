<?php
// reflection finds #[\Deprecated] on internal constants (from their stubs)
// and on the __call/__callStatic a Closure of a missing method goes through
foreach (['E_STRICT', 'MT_RAND_PHP', 'PHP_EOL'] as $name) {
    $r = new ReflectionConstant($name);
    foreach ($r->getAttributes() as $attr) {
        var_dump($attr->getName(), $attr->getArguments());
        $d = $attr->newInstance();
        var_dump($d->since, $d->message);
    }
    var_dump($r->isDeprecated());
}

class Clazz {
    #[\Deprecated]
    function __call(string $name, array $params) {}
    #[\Deprecated("due to some reason")]
    static function __callStatic(string $name, array $params) {}
}
class Sub extends Clazz {}

$foo = new Sub;
foreach ([Closure::fromCallable([$foo, 'test']), $foo->test(...), Closure::fromCallable('Clazz::test'), Clazz::test(...), Sub::other(...)] as $closure) {
    $rf = new ReflectionFunction($closure);
    $attrs = $rf->getAttributes();
    var_dump(count($attrs), $attrs ? $attrs[0]->newInstance()->message : null, $rf->isDeprecated());
}
