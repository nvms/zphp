<?php
// parent::__construct() of a private constructor runs only on an object of
// the constructor's own class

class Base {
    private function __construct() {
        echo __METHOD__, "\n";
    }

    static function make() {
        return new static;
    }

    function again() {
        self::__construct();
    }
}

class Child extends Base {
    function __construct() {
        echo __METHOD__, "\n";
        try {
            parent::__construct();
        } catch (Error $e) {
            echo get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
}

$b = Base::make();
$b->again();
new Child;
Child::make();
