<?php
try {
    class B extends A {}
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump(class_exists("B", false));
spl_autoload_register(function ($class) {
    echo "autoload $class\n";
    if ($class === "P") {
        class X extends Q {}
    }
});
try {
    class Q extends P {}
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
class Later extends Base {}
class Base {}
var_dump(get_parent_class(new Later));
