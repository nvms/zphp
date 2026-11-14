<?php
// get_class_methods, method_exists, property_exists, is_a, is_subclass_of
// and trait_exists: argument checks and which names they autoload

spl_autoload_register(function ($name) {
    echo "autoload($name)\n";
    if ($name === 'Loaded') {
        eval('class Loaded { public $prop; private static $hidden; function m() {} }');
    }
    if ($name === 'LoadedTrait') {
        eval('trait LoadedTrait {}');
    }
});

interface Base { function fromBase(); }
interface I extends Base { function pubI(); }

class P {
    private function privP() {}
    protected function protP() {}
    public function pubP() {}
    private static function privStaticP() {}
}
class C extends P {
    private function privC() {}
    public function pubC() {}
    public static function listFrom($what) { return get_class_methods($what); }
}
class D extends C {}

function show($f) {
    try {
        var_dump($f());
    } catch (TypeError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

echo "-- get_class_methods\n";
show(fn() => get_class_methods('I'));
show(fn() => get_class_methods('D'));
show(fn() => C::listFrom('D'));
show(fn() => C::listFrom(new D));
show(fn() => get_class_methods('NoSuchClass'));
show(fn() => get_class_methods(''));
show(fn() => get_class_methods(42));
show(fn() => get_class_methods(null));
show(fn() => get_class_methods([]));
show(fn() => get_class_methods('Loaded'));

echo "-- method_exists\n";
show(fn() => method_exists('C', 'privP'));
show(fn() => method_exists(new C, 'privP'));
show(fn() => method_exists('C', 'privStaticP'));
show(fn() => method_exists(new D, 'privStaticP'));
show(fn() => method_exists('P', 'privP'));
show(fn() => method_exists('', 'x'));
show(fn() => method_exists(1.5, 'x'));
show(fn() => method_exists(true, 'x'));

echo "-- property_exists\n";
show(fn() => property_exists('Loaded', 'prop'));
show(fn() => property_exists('Loaded', 'hidden'));
show(fn() => property_exists('Missing', 'prop'));
show(fn() => property_exists(10, 'prop'));
show(fn() => property_exists(null, 'prop'));

echo "-- is_a / is_subclass_of\n";
show(fn() => is_a('D', 'P'));
show(fn() => is_a('D', 'P', true));
show(fn() => is_a('Undef1', 'P', true));
show(fn() => is_a(new D, 'Undef2'));
show(fn() => is_a(new D, 'D'));
show(fn() => is_subclass_of('D', 'P'));
show(fn() => is_subclass_of('D', 'P', false));
show(fn() => is_subclass_of('Undef3', 'P'));
show(fn() => is_subclass_of('Undef4', 'P', false));
show(fn() => is_subclass_of(new D, 'Undef5'));
show(fn() => is_subclass_of('D', 'D'));
show(fn() => is_subclass_of('D', 'Base'));
show(fn() => is_subclass_of(5, 'P'));

echo "-- trait_exists\n";
show(fn() => trait_exists('LoadedTrait'));
show(fn() => trait_exists('OtherTrait'));
show(fn() => trait_exists('NotLoaded', false));

echo "-- names that never reach an autoloader\n";
show(fn() => class_exists(''));
show(fn() => class_exists('bad name'));
show(fn() => class_exists('bad-name'));
show(fn() => class_exists('Ok\\Name_1'));
show(fn() => interface_exists("nul\0byte"));
