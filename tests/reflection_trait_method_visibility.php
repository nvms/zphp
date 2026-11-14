<?php
// reflection reads a trait's own methods' modifiers from the trait

trait T {
    private function priv($a = self::class) {}
    protected function prot() {}
    public function pub() {}
    private static function privStatic() {}
    final public function fin() {}
}

class B {
    use T;
}

foreach (['T', 'B'] as $class) {
    foreach (['priv', 'prot', 'pub', 'privStatic', 'fin'] as $method) {
        $m = new ReflectionMethod($class, $method);
        echo $class, "::", $method, " ", implode(' ', Reflection::getModifierNames($m->getModifiers())),
            " private=", var_export($m->isPrivate(), true),
            " static=", var_export($m->isStatic(), true), "\n";
    }
}
echo new ReflectionMethod('T', 'priv');
echo new ReflectionMethod('B', 'priv');
