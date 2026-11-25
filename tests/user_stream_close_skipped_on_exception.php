<?php
// a user stream closed while an exception is pending (a read that threw
// during require or file_get_contents) gets no stream_close call, as php
// calls no user code then; a later fclose does call it
class Loader {
    public $context;
    function stream_open($p, $m, $o, &$opened) { return true; }
    function stream_read($n) {
        echo "stream_read\n";
        throw new Exception("Message");
    }
    function stream_eof() { return false; }
    function __call($m, $a) {
        echo "$m\n";
    }
}
stream_wrapper_register('abc', 'Loader');
try {
    require 'abc://';
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    file_get_contents('abc://x');
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
$f = fopen('abc://y', 'r');
try {
    fread($f, 10);
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
var_dump(fclose($f));
