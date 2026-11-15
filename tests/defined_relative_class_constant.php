<?php
// defined() and constant() resolve self::, parent:: and static:: against the
// calling scope, and fail where there is none

class Base {
    const X = 'base x';
    public static function probe() {
        var_dump(defined('static::OK'), defined('self::X'), defined('SELF::X'), defined('Static::Missing'));
        if (defined('static::OK')) echo constant('static::OK'), "\n";
        echo constant('self::X'), "\n";
        try {
            var_dump(defined('parent::X'));
        } catch (Error $e) {
            echo get_class($e), ': ', $e->getMessage(), "\n";
        }
    }
}

class Child extends Base {
    const OK = 'child ok';
    public static function up() {
        var_dump(defined('parent::X'), constant('parent::X'));
    }
    public function inst() {
        var_dump(defined('static::OK'), constant('static::OK'));
    }
}

Base::probe();
Child::probe();
Child::up();
(new Child)->inst();

foreach (['self::X', 'static::X', 'parent::X'] as $name) {
    try {
        var_dump(defined($name));
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
    try {
        var_dump(constant($name));
    } catch (Error $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
