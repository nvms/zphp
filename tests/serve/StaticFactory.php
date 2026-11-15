<?php
// autoloaded on each request by /static-self in app.php: the static call
// site in app.php must declare this class again before its method runs

class StaticFactory {
    public static function create() {
        return self::make('self') . ' ' . static::class;
    }
    private static function make($via) {
        return "made via $via";
    }
}
