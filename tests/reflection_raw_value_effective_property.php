<?php
// ReflectionProperty's raw accessors use the property the object's class
// declares, unless it is private to the reflected class; a raw write that
// creates a dynamic property is deprecated as any other

#[AllowDynamicProperties]
class Base {
    private $privateProp = 'Base private';
    public $virtualProp {
        get { return 'virtual'; }
        set { echo "Base set\n"; }
    }
}

class Test extends Base {
    private $privateProp = 'Test private' {
        get { echo "Test get\n"; return $this->privateProp; }
        set { echo "Test set\n"; $this->privateProp = $value; }
    }
    public $virtualProp {
        get { echo "Test get\n"; return $this->virtualProp; }
        set { echo "Test set\n"; $this->virtualProp = $value; }
    }
    public $dynamicProp = 'declared in Test';
    public static $changedProp = 'static';
}

function attempt(callable $f) {
    try {
        $r = $f();
        if ($r !== null) var_dump($r);
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}

foreach (['privateProp', 'virtualProp'] as $name) {
    echo "# $name\n";
    $ref = new ReflectionProperty(Base::class, $name);
    $o = new Test();
    attempt(fn () => $ref->setRawValue($o, 42));
    attempt(fn () => $ref->getRawValue($o));
    attempt(fn () => $ref->setRawValueWithoutLazyInitialization($o, 43));
    attempt(fn () => $ref->getRawValue($o));
}

$scope = new Base();
$scope->dynamicProp = 'dynamic on Base';
$scope->changedProp = 'dynamic on Base';
foreach (['dynamicProp', 'changedProp'] as $name) {
    echo "# $name\n";
    $ref = new ReflectionProperty($scope, $name);
    $o = new Test();
    attempt(fn () => $ref->setRawValue($o, 42));
    attempt(fn () => $ref->getRawValue($o));
    attempt(fn () => $ref->setRawValueWithoutLazyInitialization($o, 43));
    attempt(fn () => $ref->getRawValue($o));
}

class Plain {
    public $a;
}
set_error_handler(function ($no, $msg) {
    echo "error $no: $msg\n";
    return true;
});
$b = new Plain();
$b->dyn = 1;
$ref = new ReflectionProperty($b, 'dyn');
$fresh = new Plain();
var_dump($ref->getRawValue($fresh));
$ref->setRawValue($fresh, 2);
var_dump($fresh->dyn);
