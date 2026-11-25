<?php
// closing a stream that was written flushes it, and a failed flush (a user
// stream whose stream_flush returns false, or that has none) fails fclose,
// file_put_contents and copy
class NoFlush {
    public $context;
    function stream_open($p, $m) { return true; }
    function stream_write($d) { return strlen($d); }
    function stream_read($n) { return ''; }
    function stream_eof() { return true; }
    function url_stat($p, $f) { return false; }
}
class Flush extends NoFlush {
    static $ret = false;
    function stream_flush() { echo "flush\n"; return self::$ret; }
}
stream_wrapper_register('noflush', 'NoFlush');
stream_wrapper_register('flush', 'Flush');
$s = fopen('noflush://x', 'r+'); var_dump(fclose($s));
$s = fopen('noflush://x', 'r+'); fwrite($s, 'a'); var_dump(fclose($s));
$s = fopen('flush://x', 'r+'); var_dump(fclose($s));
$s = fopen('flush://x', 'r+'); fwrite($s, 'a'); var_dump(fclose($s));
$s = fopen('flush://x', 'r+'); fwrite($s, 'a'); var_dump(fflush($s), fclose($s));
var_dump(file_put_contents('noflush://x', 'abc'));
var_dump(file_put_contents('flush://x', 'abc'));
var_dump(file_put_contents('flush://x', ''));
$src = tempnam(sys_get_temp_dir(), 'zphp');
file_put_contents($src, 'data');
var_dump(copy($src, 'flush://x'));
var_dump(copy($src, 'noflush://x'));
Flush::$ret = true;
$s = fopen('flush://x', 'r+'); fwrite($s, 'a'); var_dump(fclose($s));
var_dump(file_put_contents('flush://x', 'abc'));
var_dump(copy($src, 'flush://x'));
unlink($src);
