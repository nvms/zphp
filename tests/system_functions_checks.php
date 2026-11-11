<?php
// argument checks and results of small system functions, as php's
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "  [$no] $msg\n";
    return true;
});

function attempt(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

attempt(fn() => sleep(-1));
attempt(fn() => usleep(-5));
attempt(fn() => sleep(0));
attempt(fn() => putenv(""));
attempt(fn() => putenv("=x"));
attempt(fn() => putenv("ZPHP_TEST_VAR=1"));
attempt(fn() => getenv("ZPHP_TEST_VAR"));

foreach (["", "ab", "x", "a", "s", "n", "r", "v", "m"] as $mode) {
    attempt(fn() => php_uname($mode) === php_uname($mode) ? strlen(php_uname($mode)) > 0 : null);
}
var_dump(php_uname() === implode(" ", [php_uname("s"), php_uname("n"), php_uname("r"), php_uname("v"), php_uname("m")]));

var_dump(strlen(uniqid()), strlen(uniqid("", true)), strlen(uniqid(99999)), strlen(uniqid(1, true)));
var_dump(preg_match('/^[0-9a-f]{13}\d\.\d{8}$/', uniqid("", true)));

var_dump(getservbyname("http", "tcp"), getservbyname("nonexistent-service", "tcp"));
var_dump(getservbyport(80, "tcp"), getservbyport(65000, "nonexistent"));
var_dump(getprotobyname("tcp"), getprotobynumber(17), getprotobyname("nonexistent"));
var_dump(connection_status(), connection_aborted(), CONNECTION_NORMAL, CONNECTION_ABORTED, CONNECTION_TIMEOUT);
var_dump(doubleval("1.5"), doubleval(true));
