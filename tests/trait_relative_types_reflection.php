<?php
// self and parent in a trait's declared types stay as written in
// reflection (php resolves them only in a class's own code), and a partial
// application copies its callee's types as the callee has them

if (time() > 0) {
    trait T {
        public function getSelf(object $o): self { return $o; }
        public function arg(self $o): ?self { return $o; }
        public function getStatic(object $o): static { return $o; }
    }
}
trait T2 {
    public function getSelf(object $o): self { return $o; }
    public function union(int|self $u): self|false { return false; }
}
class P {}
class C extends P { use T; }
class D extends C {}
class E { use T2; }
class F extends P {
    public function m(self $x, parent $p, int|self $u): ?self { return $x; }
}

echo new ReflectionMethod('C', 'getSelf');
echo new ReflectionMethod('C', 'arg');
echo new ReflectionMethod('E', 'getSelf');
echo new ReflectionMethod('E', 'union');
echo new ReflectionMethod('T2', 'getSelf');
echo new ReflectionMethod('F', 'm');
echo (new ReflectionMethod('C', 'getSelf'))->getReturnType(), "\n";
echo (new ReflectionMethod('T2', 'getSelf'))->getReturnType(), "\n";
echo (new ReflectionMethod('F', 'm'))->getReturnType(), "\n";
foreach ((new ReflectionMethod('C', 'arg'))->getParameters() as $p) echo $p->getType(), "\n";
foreach ((new ReflectionMethod('E', 'union'))->getParameters() as $p) echo $p->getType(), "\n";
foreach ((new ReflectionMethod('F', 'm'))->getParameters() as $p) echo $p->getType(), "\n";

$c = new C;
echo new ReflectionFunction($c->getSelf(?));
echo new ReflectionFunction($c->arg(?));
echo new ReflectionFunction($c->getStatic(?));
echo new ReflectionFunction((new E)->getSelf(?));
$f = new F;
echo new ReflectionFunction($f->m(?, ?, ?));
foreach ((new ReflectionFunction($f->m(?, ?, ?)))->getParameters() as $p) echo $p->getType(), "\n";
echo (new ReflectionFunction($f->m(?, ?, ?)))->getReturnType(), "\n";
echo (new ReflectionFunction($c->arg(?)))->getReturnType(), "\n";

$self = $c->getSelf(?);
var_dump($self($c), $self(new D));
try {
    $self(new stdClass);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
$static = (new D)->getStatic(?);
try {
    $static(new C);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
