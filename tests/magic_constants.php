<?php

function test_func() {
    return __FUNCTION__;
}
echo test_func() . "\n";

class Foo {
    public function bar() {
        echo __FUNCTION__ . "\n";
        echo __CLASS__ . "\n";
        echo __METHOD__ . "\n";
    }

    public static function baz() {
        echo __FUNCTION__ . "\n";
        echo __CLASS__ . "\n";
        echo __METHOD__ . "\n";
    }
}

(new Foo())->bar();
Foo::baz();

echo "global_func:" . __FUNCTION__ . "\n";
echo "global_class:" . __CLASS__ . "\n";
echo "global_method:" . __METHOD__ . "\n";
echo "line:" . __LINE__ . "\n";

$fn = function () {
    return str_starts_with(__FUNCTION__, '{closure') ? 'closure' : 'not_closure';
};
echo $fn() . "\n";

trait Loggable {
    public function traitInfo() {
        echo __TRAIT__ . "\n";
    }
}

class Post {
    use Loggable;
}
(new Post())->traitInfo();

enum Color: string {
    case Red = 'red';
    case Blue = 'blue';

    public const NAMES = ['RED', 'BLUE'];
    public const VALUES = ['red', 'blue'];
}

echo var_export(Color::NAMES, true) . "\n";
echo var_export(Color::VALUES, true) . "\n";
echo var_export(defined('Color::Red'), true) . "\n";
echo var_export(defined('Color::NAMES'), true) . "\n";
echo constant('Color::Red')->name . "\n";
echo var_export(constant('Color::NAMES'), true) . "\n";
