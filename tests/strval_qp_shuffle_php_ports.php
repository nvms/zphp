<?php
// strval's conversions, quoted_printable_encode's line breaking, md5_file's
// empty path, and shuffles that draw from mt_rand's engine
set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });
function t(callable $f) {
    try {
        var_dump($f());
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
class NoString {}
t(fn() => strval([1]));
t(fn() => strval(new NoString));
t(fn() => strval(fn() => 1));
t(fn() => strval(1.5));

t(fn() => quoted_printable_encode(1));
t(fn() => quoted_printable_encode(""));
t(fn() => quoted_printable_encode(str_repeat("ą", 30)));
t(fn() => quoted_printable_encode(str_repeat("a=", 40) . " \r\nend\r"));
t(fn() => quoted_printable_encode("\0\x7f\xff tab\there"));

t(fn() => md5_file(""));
t(fn() => sha1_file(""));

mt_srand(42);
var_dump(str_shuffle("abcdefghij"));
$a = range(1, 10);
shuffle($a);
echo implode(",", $a), "\n";
var_dump(mt_rand(1, 100));
