<?php
// new takes a class named by a static property reached through a variable
// class name (php's new_variable '::' simple_variable)
class Test {
    public static $className = 'stdClass';
    public static $other = 'ArrayObject';
}
$test = 'Test';
$weird = [0 => (object) ['foo' => 'Test']];
var_dump(new $test::$className);
var_dump(new $weird[0]->foo::$className);
var_dump(get_class(new $test::$other([1])));
var_dump(new Test::$className());
