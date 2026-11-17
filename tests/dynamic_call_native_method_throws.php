<?php
// a native method called through a callable value that throws lands in the
// caller's catch with the exception, not a value the call left behind
$rc = new ReflectionClass("PDO");
$o = $rc->newInstanceWithoutConstructor();
$f = [$o, "__construct"];
foreach ([[null], ["nodriver"], [null, null]] as $args) {
    try {
        @$f(...$args);
        echo "no exception\n";
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
try {
    $f("");
} catch (PDOException $e) {
    echo "caught ", $e->getMessage(), "\n";
}
try {
    call_user_func_array($f, ["dsn" => ""]);
} catch (PDOException $e) {
    echo "caught ", $e->getMessage(), "\n";
}
function g($f) {
    try {
        return $f("x");
    } finally {
        echo "finally\n";
    }
}
try {
    g($f);
} catch (PDOException $e) {
    echo "outer ", $e->getMessage(), "\n";
}
echo "done\n";
