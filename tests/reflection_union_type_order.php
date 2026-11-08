<?php
// reflection prints a union type as php orders it, resolves self in it, and
// gives an intersection member of a union as an intersection type
class Shape {
    public int|string $id;
    public function f(int|string|null $a, iterable|bool $b, self|int $c, (Countable&Traversable)|array|null $d, float|int|false $e): object|array|null {}
}
echo (new ReflectionProperty('Shape', 'id'))->getType(), "\n";
$m = new ReflectionMethod('Shape', 'f');
foreach ($m->getParameters() as $p) {
    $t = $p->getType();
    echo $t, ' [', implode(', ', array_map(fn ($u) => get_class($u) . ' ' . $u, $t->getTypes())), "]\n";
}
echo $m->getReturnType(), "\n";
