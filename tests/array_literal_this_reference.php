<?php
// `&$this` in an array literal is a reference only the array holds, so
// array functions copy it as a value and a by-reference callback warns
function ref(&$ref) { var_dump($ref); }
class A {
    function run() {
        $args = [&$this];
        var_dump($args);
        $copy = array_slice($args, 0, 1);
        var_dump($copy);
        call_user_func_array("ref", $copy);
    }
}
(new A)->run();
