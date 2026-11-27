<?php
// a concatenation past memory_limit is reported as a trampoline's frame is
// entered: a string counts its header and terminator as php's zend_string,
// so the 2MB result takes a huge block of its own beyond the 4MB limit
ini_set('memory_limit', '4M');
ini_set('log_errors', '0');
ini_set("display_errors", "1");

class C {
    static function __callStatic($name, $args)
    {
        echo "not reached\n";
    }
}

register_shutdown_function(function () {
    $e = error_get_last();
    echo $e['message'], " on line ", $e['line'], "\n";
    var_dump(isset($e['trace']));
});

$a = str_repeat('a', 1024 * 1024);
echo "before\n";
C::test(1, 2, 3, 4, $a . $a);
