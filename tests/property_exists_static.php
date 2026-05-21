<?php
// regression: property_exists() on an object instance also finds static
// properties (and properties declared on ancestor classes). zphp's object
// path previously only checked instance properties and missed statics.

class Base {
    public static $baseStatic = 1;
    public $baseInstance = 2;
}
class Child extends Base {
    public static $childStatic = 3;
    public $childInstance = 4;
    private $childPrivate = 5;
}

$c = new Child;

// static property of the object's own class
var_dump(property_exists($c, 'childStatic'));   // true
// instance property of the object's own class
var_dump(property_exists($c, 'childInstance')); // true
// private property still counts (property_exists ignores visibility)
var_dump(property_exists($c, 'childPrivate'));  // true
// inherited static property
var_dump(property_exists($c, 'baseStatic'));    // true
// inherited instance property
var_dump(property_exists($c, 'baseInstance'));  // true
// missing property
var_dump(property_exists($c, 'missing'));       // false

// the class-name form behaves the same
var_dump(property_exists('Child', 'childStatic'));
var_dump(property_exists('Child', 'baseStatic'));

// a dynamically added property
$c->extra = 9;
var_dump(property_exists($c, 'extra'));         // true

// static-only class
class Config {
    public static $debug = false;
    public static $level = 1;
}
var_dump(property_exists(new Config, 'debug'));
var_dump(property_exists(new Config, 'level'));
var_dump(property_exists(new Config, 'absent'));
