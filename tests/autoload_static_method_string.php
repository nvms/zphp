<?php
// an autoloader registered as "Class::method" runs with that class as the
// called scope

class A {
    static function load($name) {
        echo get_called_class(), " loads $name\n";
        if ($name === 'Found') {
            eval('class Found {}');
        }
    }
}
class B extends A {}

spl_autoload_register('B::load');
var_dump(class_exists('Found'));
var_dump(class_exists('Missing'));
