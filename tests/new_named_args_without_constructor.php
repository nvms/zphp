<?php
// a class without a constructor takes positional arguments it ignores, but
// a named one is an unknown parameter
class Plain {}
var_dump(new Plain(1, 2));
foreach ([fn() => new stdClass(x: "nope"), fn() => new Plain(1, y: 2), fn() => new Plain(...['a' => 1])] as $f) {
    try {
        $f();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
try {
    new Missing(x: 1);
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
