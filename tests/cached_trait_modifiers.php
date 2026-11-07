<?php
// trait methods keep their visibility and final flag when the file holding
// the trait is loaded from the compile cache (the second run onward)
require __DIR__ . '/include/cached_traits/traits.php';

abstract class Base { use CachedGuarded, CachedSealed; }
class Child extends Base { protected function guarded() { return 'child'; } }

$m = new ReflectionMethod('Base', 'guarded');
var_dump($m->isProtected(), (new ReflectionMethod('Base', 'sealed'))->isFinal());
print_r(get_class_methods('Child'));
try {
    (new Child)->guarded();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
