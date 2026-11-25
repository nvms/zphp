<?php
// writing a readonly property the scope can't see is an access error, as
// the visibility check comes first; one it can see is a readonly error
class A {
    public function __construct(private readonly int $x, protected readonly int $y, public readonly int $z) {}
    public function setX() { $this->x = 5; }
}
class B extends A {
    public function setY() { $this->y = 6; }
}
$a = new B(1, 2, 3);
foreach (['x', 'y', 'z'] as $p) {
    try {
        $a->$p = 9;
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
foreach (['setX', 'setY'] as $m) {
    try {
        $a->$m();
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
