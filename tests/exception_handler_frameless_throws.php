<?php
// throwables that escape code the engine runs with no frame below reach the
// exception handler: one the handler throws after installing another, a
// destructor at shutdown, and an output handler flushed at shutdown
class Foo { public function __destruct() { throw new Exception(__METHOD__); } }
set_exception_handler(function (Throwable $e) {
    echo "Caught: ", $e->getMessage(), "\n";
    set_exception_handler(function (Throwable $e) { echo "Second: ", $e->getMessage(), "\n"; });
    throw new Exception("from handler");
});
$GLOBALS["foo"] = new Foo;
ob_start(function ($s) { if ($s === "") return ""; throw new Exception("ob"); });
throw new Exception("main");
