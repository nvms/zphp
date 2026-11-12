<?php
// data: urls as php's rfc2397 wrapper reads them, wrappers php doesn't
// know, seeks on directory handles, and the errors of socket addresses

set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });

$f = fopen('data:text/plain;charset=utf-8;name=x,hello%20world', 'r');
$meta = stream_get_meta_data($f);
var_dump($meta);
var_dump(fread($f, 5));
var_dump(fseek($f, -1, SEEK_SET), ftell($f));
var_dump(fseek($f, 2, SEEK_CUR), ftell($f));
var_dump(fwrite($f, 'x'));
var_dump(stream_get_contents($f));
fclose($f);

$f = fopen('data:;base64,SGVsbG8=', 'rb');
var_dump(stream_get_meta_data($f)['mediatype'] ?? null, stream_get_meta_data($f)['base64']);
var_dump(stream_get_contents($f));
fclose($f);

var_dump(@file_put_contents('data:,abc', 'x'));
var_dump(file_put_contents('data:,abc', 'x'));

$t = fopen('php://temp', 'w+');
fwrite($t, 'abc');
var_dump(fseek($t, -2, SEEK_SET), ftell($t));
var_dump(fseek($t, -1, SEEK_END), ftell($t));
fclose($t);

var_dump(file_get_contents('nosuchwrapper://thing'));
var_dump(file_exists('nosuchwrapper://thing'));

$dir = sys_get_temp_dir() . '/zphp_data_urls_' . getmypid();
mkdir($dir);
touch("$dir/a");
touch("$dir/b");
$d = opendir($dir);
$first = [];
while (($e = readdir($d)) !== false) $first[] = $e;
var_dump(fseek($d, 0));
$second = [];
while (($e = readdir($d)) !== false) $second[] = $e;
sort($first);
sort($second);
var_dump($first === $second, count($second));
closedir($d);
unlink("$dir/a");
unlink("$dir/b");
rmdir($dir);

trait T {
    public $context;
    function stream_open($path, $mode, $options, &$opened) { return true; }
    function stream_read($n) { return ''; }
    function stream_eof() { return true; }
}
var_dump(stream_wrapper_register('traitwrap', 'T'));
var_dump(file_get_contents('traitwrap://x'));

foreach (['tcp://localhost', 'tcp://[::1', "tcp://a\0b:80"] as $target) {
    var_dump(@stream_socket_client($target, $errno, $errstr, 1));
    var_dump($errno, $errstr);
}

var_dump(ini_get('auto_detect_line_endings'), ini_get('from'));
ini_set('auto_detect_line_endings', '1');
$f = fopen('php://memory', 'w+');
fwrite($f, "one\rtwo\rthree");
rewind($f);
while (($line = fgets($f)) !== false) var_dump($line);
fclose($f);
