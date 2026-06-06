<?php
// covers: ReflectionProperty::__construct throws ReflectionException for a
// property not declared on the class (or any ancestor); succeeds for declared,
// private, inherited, and constructor-promoted properties

class Base {
    protected int $inherited = 1;
}

class Box extends Base {
    public int $id = 0;
    private string $secret = 'x';
    public function __construct(public readonly string $sku = 'S') {}
}

function probe(string $class, string $prop): string {
    try {
        $rp = new ReflectionProperty($class, $prop);
        return "$prop: declared(mods=" . $rp->getModifiers() . ")";
    } catch (ReflectionException $e) {
        return "$prop: " . $e->getMessage();
    }
}

foreach (['id', 'secret', 'inherited', 'sku', 'missing', 'getId', ''] as $p) {
    echo probe('Box', $p), "\n";
}

// dynamic (runtime-added) property is NOT declared -> still throws
$b = new Box();
$b->dynamic = 42;
echo probe('Box', 'dynamic'), "\n";

// constructing from an object instance behaves the same as from the class name
try {
    $rp = new ReflectionProperty($b, 'nope');
    echo "from-object nope: ok\n";
} catch (ReflectionException $e) {
    echo "from-object nope: " . $e->getMessage(), "\n";
}
