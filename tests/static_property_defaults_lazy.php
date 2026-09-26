<?php
// static property defaults that read another class or a global constant are
// evaluated when the class is first used, like instance defaults, so they may
// name a class declared after this one, even one that extends it

class Base {
    public static $map = [Child::KIND => 'child'];
    public static $plain = 5;
    public static $computed = PHP_INT_SIZE * 2;
}

class Child extends Base {
    const KIND = 'k';
    public static $own = Base::class . '!';
    public $instance = Child::KIND;
}

var_dump(Base::$plain);
var_dump(Base::$map, Child::$own, Child::$computed);
Base::$computed = 'set';
var_dump(Child::$computed, (new Child)->instance);

// the first use can be an instantiation, a write, a reference or reflection
class Late { public static $a = Later::A; public static $b = [Later::A]; }
class Later { const A = 'later'; }
$ref = &Late::$a;
var_dump($ref);
Late::$b[] = 'appended';
var_dump(Late::$b);

class Reflected { public static $r = Later::A . '?'; }
$prop = new ReflectionProperty('Reflected', 'r');
var_dump($prop->getValue());
$prop->setValue(null, 'changed');
var_dump(Reflected::$r);

class Listed { public static $l = Later::A; }
var_dump((new ReflectionClass('Listed'))->getStaticProperties());
var_dump((new ReflectionClass('Listed'))->getStaticPropertyValue('l'));
var_dump(get_class_vars('Listed'));

// a child's first use resolves its parent's statics too
class StaticOnly { public static $s = Later::A . '+'; }
class WithInstance extends StaticOnly { public $i = 1; }
new WithInstance;
var_dump(StaticOnly::$s);

// a failing default throws at the use and runs again on the next one
class Failing { public static $x = Missing::A; }
for ($i = 0; $i < 2; $i++) {
    try {
        var_dump(Failing::$x);
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
