<?php
// static:: inside closures must resolve to the defining class, not the calling class

class Base {
    protected static function getItems() {
        return ['a', 'b', 'c'];
    }

    public static function buildClosure() {
        $x = 1;
        return function() use ($x) {
            return static::getItems();
        };
    }
}

class Caller {
    public static function run($closure) {
        return $closure();
    }
}

// closure defined in Base, called from Caller - static:: should resolve to Base
$closure = Base::buildClosure();
$result = Caller::run($closure);
echo implode(',', $result) . "\n";

// same pattern as Laravel's BoundMethod: static::method inside closure, called from different class
class BoundMethod {
    public static function call($callback) {
        $params = 'test';
        return static::callBound($callback, function() use ($callback, $params) {
            return static::getDeps($callback, $params);
        });
    }

    protected static function callBound($callback, $default) {
        return Util::unwrap($default);
    }

    protected static function getDeps($callback, $params) {
        return "deps:$callback:$params";
    }
}

class Util {
    public static function unwrap($value) {
        if ($value instanceof Closure) {
            return $value();
        }
        return $value;
    }
}

$result = BoundMethod::call('myFunc');
echo "$result\n";

// static:: with inheritance
class Child extends Base {
    protected static function getItems() {
        return ['x', 'y', 'z'];
    }
}

$closure = Child::buildClosure();
$result = Caller::run($closure);
echo implode(',', $result) . "\n";

// instance method closure with static::
class Foo {
    protected static $name = 'Foo';

    public function getClosure() {
        return function() {
            return static::$name;
        };
    }
}

class Bar extends Foo {
    protected static $name = 'Bar';
}

$bar = new Bar();
$closure = $bar->getClosure();
echo $closure() . "\n";
