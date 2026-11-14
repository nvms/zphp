<?php
// attributes on property hooks belong to the hook's method, and attributes
// on a set hook's parameter to that parameter
ini_set("zend.exception_ignore_args", "0");
#[Attribute]
class A { function __construct(public $v = null) {} }

#[Attribute(Attribute::TARGET_METHOD)]
class OnMethod {}

#[Attribute(Attribute::TARGET_PROPERTY)]
class OnProperty {}

class C {
    public $prop {
        #[A(1)] #[OnMethod] get => 1;
        #[A(2)] final set(#[SensitiveParameter] $value) {
            throw new Exception("set $value");
        }
    }
    public $other {
        #[OnProperty] get => 2;
    }
}

$prop = new ReflectionProperty(C::class, 'prop');
foreach ($prop->getHooks() as $kind => $hook) {
    echo $kind, ":\n";
    foreach ($hook->getAttributes() as $attr) {
        echo "  ", $attr->getName(), " ", json_encode($attr->getArguments()), "\n";
        var_dump($attr->newInstance());
    }
    foreach ($hook->getParameters() as $param) {
        foreach ($param->getAttributes() as $attr) echo "  param ", $attr->getName(), "\n";
    }
}
var_dump(count($prop->getAttributes()));

try {
    (new ReflectionProperty(C::class, 'other'))->getHook(PropertyHookType::Get)->getAttributes()[0]->newInstance();
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

try {
    $c = new C;
    $c->prop = "secret";
} catch (Exception $e) {
    echo $e->getTraceAsString(), "\n";
}
