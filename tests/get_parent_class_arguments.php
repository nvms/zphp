<?php
// get_parent_class() without arguments is deprecated; an argument that names
// no class is a TypeError naming its type

interface I {}
class Base {}
class Child extends Base {
    function parentOfThis() {
        return get_parent_class();
    }
}

var_dump((new Child)->parentOfThis());

set_error_handler(function ($severity, $message) {
    throw new Exception($message);
});
try {
    (new Child)->parentOfThis();
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
restore_error_handler();

var_dump(get_parent_class(new Child), get_parent_class('Child'), get_parent_class('Base'), get_parent_class('I'));
foreach (['', '[[[[', ' ', [], 1, 1.5, null, true] as $arg) {
    try {
        var_dump(get_parent_class($arg));
    } catch (TypeError $e) {
        echo $e->getMessage(), "\n";
    }
}

spl_autoload_register(function ($name) {
    echo "autoload $name\n";
    if ($name === 'Late') {
        eval('class Late extends Base {}');
    }
});
var_dump(get_parent_class('Late'));
