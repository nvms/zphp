<?php
function foo($a, $b, $c) {

}

class C {
    function f($a, $b, $c) {
    }
}

try {
    foo(?);
} catch (Error $ex) {
    printf("%s: %s\n", $ex::class, $ex->getMessage());
}

try {
    foo(?, ?, ?, ?);
} catch (Error $ex) {
    printf("%s: %s\n", $ex::class, $ex->getMessage());
}

try {
    $c = new C();
    $c->f(?);
} catch (Error $ex) {
    printf("%s: %s\n", $ex::class, $ex->getMessage());
}

try {
    property_exists(?);
} catch (Error $ex) {
    printf("%s: %s\n", $ex::class, $ex->getMessage());
}

try {
    usleep(?, ?);
} catch (Error $ex) {
    printf("%s: %s\n", $ex::class, $ex->getMessage());
}

try {
    foo(?, ?, ?, ?, ...);
} catch (Error $ex) {
    printf("%s: %s\n", $ex::class, $ex->getMessage());
}

/* It is allowed to specify less than the number of required params, when there
 * is a variadic placeholder */
foo(?, ...);

?>
