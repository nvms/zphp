<?php
// error_log() and dl() take their paths as php's path parameters do: a NUL
// byte is a ValueError, as is an empty or missing file for message type 3;
// type 2 (tcp/ip) isn't available
$tries = [
    fn() => error_log("test", 3, null),
    fn() => error_log("test", 3, ""),
    fn() => error_log("test", 3),
    fn() => error_log("test", 3, "a\0b"),
    fn() => error_log("test", 2, "127.0.0.1"),
    fn() => dl("foo\0bar"),
];
foreach ($tries as $try) {
    try {
        var_dump($try());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
