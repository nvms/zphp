<?php

class Counter {
    public static $count = 0;

    public static function increment() {
        self::$count += 1;
    }

    public static function getCount() {
        return self::$count;
    }
}

echo Counter::$count . "\n";
Counter::increment();
Counter::increment();
Counter::increment();
echo Counter::$count . "\n";
echo Counter::getCount() . "\n";

Counter::$count = 100;
echo Counter::$count . "\n";

// static with inheritance
class Base {
    public static $name = "Base";

    public static function identify() {
        return self::$name;
    }
}

class Child extends Base {
    public static $name = "Child";
}

echo Base::$name . "\n";
echo Child::$name . "\n";
echo Base::identify() . "\n";

// static method calling other static method
class MathHelper {
    public static function double($n) {
        return $n * 2;
    }

    public static function quadruple($n) {
        return self::double(self::double($n));
    }
}

echo MathHelper::double(5) . "\n";
echo MathHelper::quadruple(3) . "\n";

// mix of static and instance
class Config {
    public static $debug = false;
    public $name;

    public function __construct($name) {
        $this->name = $name;
    }

    public static function enableDebug() {
        self::$debug = true;
    }

    public function describe() {
        $mode = self::$debug ? "debug" : "normal";
        return $this->name . " (" . $mode . ")";
    }
}

$c = new Config("app");
echo $c->describe() . "\n";
Config::enableDebug();
echo $c->describe() . "\n";
echo Config::$debug ? "true" : "false";
echo "\n";
