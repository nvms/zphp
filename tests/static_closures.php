<?php

// late static binding in closures
class Base {
    public static string $type = "base";

    public static function getType() {
        return static::$type;
    }

    public static function transform($arr) {
        return array_map(function($v) {
            return static::$type . ":" . $v;
        }, $arr);
    }

    public static function filter($arr) {
        return array_filter($arr, function($v) {
            return $v === static::$type;
        });
    }
}

class Child extends Base {
    public static string $type = "child";
}

// basic late static binding
echo Base::getType() . "\n";
echo Child::getType() . "\n";

// late static binding in array_map callback
$result = Child::transform(["a", "b"]);
echo implode(",", $result) . "\n";

// late static binding in array_filter callback
$items = ["base", "child", "other", "child"];
$filtered = Child::filter($items);
echo count($filtered) . "\n";
echo implode(",", $filtered) . "\n";

// static:: in closure bound to instance
class Factory {
    public $prefix;

    public function __construct($p) { $this->prefix = $p; }

    public function maker() {
        return function($name) {
            return $this->prefix . ":" . static::label() . ":" . $name;
        };
    }

    public static function label() { return "factory"; }
}

class SpecialFactory extends Factory {
    public static function label() { return "special"; }
}

$f = new SpecialFactory("pre");
$maker = $f->maker();
echo $maker("test") . "\n";

echo "done\n";
