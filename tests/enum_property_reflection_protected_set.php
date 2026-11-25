<?php
// an enum's name and value properties are readonly with an implicit
// protected(set), as php declares readonly properties
enum U { case A; }
enum B: string { case X = 'x'; }
foreach ([U::class, B::class, \Random\IntervalBoundary::class] as $c) {
    foreach ((new ReflectionClass($c))->getProperties() as $p) {
        echo $c, '::', $p->getName(), ' mods=', $p->getModifiers(), ' ', implode(' ', Reflection::getModifierNames($p->getModifiers())),
            ' ro=', var_export($p->isReadOnly(), true), ' pset=', var_export($p->isProtectedSet(), true), ' privset=', var_export($p->isPrivateSet(), true),
            ' final=', var_export($p->isFinal(), true), ' virtual=', var_export($p->isVirtual(), true), ' type=', $p->getType(), "\n";
        echo (string)$p;
    }
}
enum U2 { case A; public function f() { $this->name = 'z'; } }
enum B2: string { case X = 'x'; }
$tries = [
    fn() => U2::A->name = 'x',
    fn() => B2::X->value = 'y',
    fn() => U2::A->f(),
    function () { $r = &U2::A->name; },
    function () { unset(B2::X->value); },
    fn() => (new ReflectionProperty(U2::class, 'name'))->setValue(U2::A, 'q'),
];
foreach ($tries as $t) {
    try { $t(); echo "ok\n"; } catch (Error $e) { echo get_class($e), ': ', $e->getMessage(), "\n"; }
}
