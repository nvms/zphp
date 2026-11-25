<?php
// a hooked property's default is a constant expression evaluated when the
// class is first used, like any property default: a class may be declared
// before the constant it names exists
class A {
    public $prop = C { get => $this->prop; }
}
class B extends A {
    public $prop { get => 42; }
}
echo "declared\n";
try {
    new A;
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
const C = 'c value';
var_dump((new A)->prop, (new B)->prop);

class D {
    const X = 5;
    public int $n = self::X * 2 {
        get => $this->n + 1;
        set => $value * 3;
    }
    public array $list = [1, 2] {
        get => $this->list;
    }
}
$d = new D;
var_dump($d->n, $d->list);
$d->n = 2;
var_dump($d->n);
var_dump((new ReflectionProperty(D::class, 'n'))->getDefaultValue());
