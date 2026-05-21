<?php
// regression: get_class_methods() returns methods in declaration order.
// zphp iterated the method hash map, producing a non-deterministic order
// that did not match PHP (e.g. a static method appearing before an
// earlier-declared instance method).

class Service {
    public function __construct() {}
    public function connect() {}
    public static function instance() {}
    public function disconnect() {}
    public function query() {}
    protected function internal() {}
    private function secret() {}
}
print_r(get_class_methods('Service'));

// inheritance: child methods first (declaration order), then parent
class Repository extends Service {
    public function find() {}
    public function save() {}
    public function connect() {}
}
print_r(get_class_methods('Repository'));

// from an instance
print_r(get_class_methods(new Repository));

// a class with only static methods
class Helpers {
    public static function one() {}
    public static function two() {}
    public static function three() {}
}
print_r(get_class_methods('Helpers'));
