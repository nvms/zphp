<?php
// php 8.6 lets readonly properties declare a default; the property starts
// initialized, so no write gets through, not even in the constructor
enum E {
    case Case;
}

class Test {
    public readonly int $prop = 1;
    public readonly string $className = self::class;
    public readonly ?string $nullable = null;
    public readonly array $array = [1, "two" => 2];
    public readonly E $enum = E::Case;
    public readonly string $enumString = E::Case->name;
    public readonly int $later;

    public function __construct() {
        try {
            $this->prop = 5;
        } catch (Error $e) {
            echo get_class($e), ': ', $e->getMessage(), "\n";
        }
        $this->later = 7;
    }
}

$test = new Test;
var_dump($test->prop, $test->className, $test->nullable, $test->array, $test->enum, $test->enumString, $test->later);
try {
    $test->prop = 2;
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    unset($test->prop);
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
var_dump(isset($test->prop));

class ParentDefault {
    public readonly int $prop = 1;
}
class ChildInherits extends ParentDefault {}
class ChildOverrides extends ParentDefault {
    public readonly int $prop = 2;
}
class PrivateParent {
    private readonly int $prop = 3;
    public function getParentProp(): int { return $this->prop; }
}
class PrivateChild extends PrivateParent {
    public readonly int $prop = 4;
}
var_dump((new ChildInherits)->prop, (new ChildOverrides)->prop);
$p = new PrivateChild;
var_dump($p->getParentProp(), $p->prop);

class Vis {
    public readonly int $default = 1;
    public private(set) readonly int $private = 2;
    public protected(set) readonly int $protected = 3;
    public public(set) readonly int $public = 4;
}
$v = new Vis;
foreach (['default', 'private', 'protected', 'public'] as $name) {
    try {
        $v->$name = 42;
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    echo $name, ' ', $v->$name, "\n";
}

readonly class Ro {
    public int $bar = 1;
    public ?string $nullable = null;
}
$ro = new Ro;
var_dump($ro->bar, $ro->nullable);
try {
    $ro->bar = 3;
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

interface I {
    public int $prop { get; }
}
class Impl implements I {
    public readonly int $prop = 42;
}
var_dump((new Impl)->prop);

// clone keeps the value
$c = clone $test;
var_dump($c->prop);
$r = new ReflectionProperty(Test::class, 'prop');
var_dump($r->hasDefaultValue(), $r->getDefaultValue(), $r->isReadOnly(), $r->isInitialized($test));
var_dump(get_class_vars('Test'));
var_dump(serialize($test));
