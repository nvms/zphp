<?php
// redeclaring a class is E_COMPILE_ERROR even when the declaration is bound
// at run time
register_shutdown_function(function () {
    $e = error_get_last();
    var_dump($e['type'], str_replace(__FILE__, 'FILE', $e['message']), $e['line']);
});
class Foo {}
if (count($argv) > 0) {
    class Foo {}
}
