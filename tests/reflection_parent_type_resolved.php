<?php
// a parent type is resolved to the parent class while compiling, as self is
class Base {}
class Child extends Base {
    function take(parent $x): parent { return $x; }
    function maybe(?parent $x): ?parent { return $x; }
    function me(self $x): self { return $x; }
}
foreach (['take', 'maybe', 'me'] as $m) {
    $r = new ReflectionMethod('Child', $m);
    $t = $r->getParameters()[0]->getType();
    var_dump($t->getName(), (string) $t, $t->allowsNull(), (string) $r->getReturnType());
}
echo new ReflectionMethod('Child', 'take');
