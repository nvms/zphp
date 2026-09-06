<?php
// Widening a setter is legal, including through an intermediate declaration.
class SetterBase { public protected(set) int $x; }
class SetterMiddle extends SetterBase { public int $x; }
class SetterLeaf extends SetterMiddle { public int $x; }
// A parent's private property is an independent declaration.
class PrivateBase { private int $x; }
class PrivateChild extends PrivateBase { public private(set) int $x; }
// A virtual getter has no inherited write-visibility contract.
class GetterBase { public int $x { get => 1; } }
class GetterChild extends GetterBase { public protected(set) int $x = 2; }
class HookCases {
    public public(set) int $symmetric { get => 1; }
    public private(set) int $backed { get => $this->backed; }
    public protected(set) int $virtual { get => 1; set {} }
}
class ReadonlyProperties {
    public readonly int $a;
    protected readonly int $b;
    private readonly int $c;
    public function __construct(public readonly int $promoted = 1) {}
}
readonly class ReadonlyClass { public int $a; }
foreach ([ReadonlyProperties::class, ReadonlyClass::class] as $class) {
    foreach ((new ReflectionClass($class))->getProperties() as $p) {
        echo $class, '::', $p->getName(), ':', $p->getModifiers(), ':',
            (int)$p->isProtectedSet(), ':', (int)$p->isPrivateSet(), ':', (int)$p->isFinal(), "\n";
    }
}
echo "declarations OK\n";
