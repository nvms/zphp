<?php
// covers: trait static properties, static::{expr}() dynamic method calls,
//   trait static property inheritance, dynamic static dispatch

trait HasUnits {
    protected static $units = ['year', 'month', 'day', 'hour', 'minute', 'second'];

    public static function isModifiableUnit($unit) {
        return in_array($unit, static::$units, true);
    }

    public static function getUnits() {
        return static::$units;
    }
}

trait HasConfig {
    protected static $config = ['debug' => false, 'strict' => true];

    public static function getConfig() {
        return static::$config;
    }
}

class DateHelper {
    use HasUnits;
    use HasConfig;
}

// trait static properties
$units = DateHelper::getUnits();
echo count($units) . "\n";
echo $units[0] . "\n";
echo DateHelper::isModifiableUnit('year') ? "yes" : "no";
echo "\n";
echo DateHelper::isModifiableUnit('week') ? "yes" : "no";
echo "\n";

$config = DateHelper::getConfig();
echo count($config) . "\n";
echo $config['strict'] ? "strict" : "relaxed";
echo "\n";

// dynamic static method call: Class::{expr}()
class Router {
    public static function getRoutes() {
        return "all-routes";
    }

    public static function getMiddleware() {
        return "all-middleware";
    }
}

$methods = ['Routes', 'Middleware'];
foreach ($methods as $m) {
    $result = Router::{'get' . $m}();
    echo $result . "\n";
}

// dynamic static with variable
$methodName = 'getUnits';
$result = DateHelper::{$methodName}();
echo count($result) . "\n";

echo "done\n";
