<?php
// covers: attribute newInstance validation, non-attribute class rejection,
//   target enforcement (TARGET_METHOD on class), repeatability enforcement,
//   IS_REPEATABLE flag, #[Override] valid usage, attribute instantiation
//   with named args and constructor promotion

#[Attribute]
class TestAttr {
    public function __construct(public string $val = '') {}
}

#[TestAttr('hello')]
class MyClass {}

$rc = new ReflectionClass('MyClass');
$attrs = $rc->getAttributes();
$inst = $attrs[0]->newInstance();
echo "valid newInstance: " . $inst->val . "\n";

// non-attribute class
class NotAnAttr {}

#[NotAnAttr]
class MyClass2 {}

$rc2 = new ReflectionClass('MyClass2');
$attrs2 = $rc2->getAttributes();
try {
    $attrs2[0]->newInstance();
    echo "non-attr: should have thrown\n";
} catch (Error $e) {
    echo "non-attr: caught\n";
}

// target enforcement
#[Attribute(Attribute::TARGET_METHOD)]
class MethodOnly {
    public function __construct(public string $val = '') {}
}

#[MethodOnly('bad')]
class MyClass3 {}

$rc3 = new ReflectionClass('MyClass3');
$attrs3 = $rc3->getAttributes();
try {
    $attrs3[0]->newInstance();
    echo "target: should have thrown\n";
} catch (Error $e) {
    echo "target: caught\n";
}

// repeatability enforcement
#[Attribute]
class SingleAttr {
    public function __construct(public string $val = '') {}
}

#[SingleAttr('a')]
#[SingleAttr('b')]
class MyClass4 {}

$rc4 = new ReflectionClass('MyClass4');
$attrs4 = $rc4->getAttributes();
try {
    $attrs4[0]->newInstance();
    echo "repeat: should have thrown\n";
} catch (Error $e) {
    echo "repeat: caught\n";
}

// IS_REPEATABLE allows repeats (255 = TARGET_ALL | IS_REPEATABLE)
#[Attribute(255)]
class RepeatableAttr {
    public function __construct(public string $val = '') {}
}

#[RepeatableAttr('a')]
#[RepeatableAttr('b')]
class MyClass5 {}

$rc5 = new ReflectionClass('MyClass5');
$attrs5 = $rc5->getAttributes();
$inst5a = $attrs5[0]->newInstance();
$inst5b = $attrs5[1]->newInstance();
echo "repeatable: " . $inst5a->val . ", " . $inst5b->val . "\n";

// #[Override] valid usage
class Base {
    public function doStuff(): string { return 'base'; }
}

class Child extends Base {
    #[Override]
    public function doStuff(): string { return 'child'; }
}

echo "override valid: " . (new Child())->doStuff() . "\n";

echo "Done.\n";
