<?php

class Config {
    const VERSION = "1.0.0";
    const MAX_RETRIES = 3;
    const DEBUG = false;
}

echo Config::VERSION . "\n";
echo Config::MAX_RETRIES . "\n";
echo Config::DEBUG === false ? "false" : "true";
echo "\n";

// constants with expressions
class MathConst {
    const PI = 3.14159;
    const TAU = 6.28318;
}

echo MathConst::PI . "\n";
echo MathConst::TAU . "\n";

// inherited class constants
class Base {
    const NAME = "base";
}

class Child extends Base {
    const CHILD_NAME = "child";
}

echo Child::NAME . "\n";
echo Child::CHILD_NAME . "\n";

// class constant alongside static properties
class Combo {
    const TYPE = "combo";
    public static $count = 0;

    public static function getType(): string {
        return self::TYPE;
    }
}

echo Combo::TYPE . "\n";
echo Combo::getType() . "\n";
