<?php
// a stream keeps the context it was opened with: its options are the
// stream's, and setting one on the stream sets it on the context. the
// default context is never attached

class NullStream
{
    public $context;
    public function stream_open($path, $mode, $options, &$opened_path) { return true; }
    public function stream_read($count) { return ''; }
    public function stream_eof() { return true; }
}
stream_wrapper_register('null', 'NullStream');

$context = stream_context_create(['demo' => ['a' => 1]]);
$file = sys_get_temp_dir() . '/zphp_stream_context_of_opened_stream.txt';
file_put_contents($file, "x");

foreach ([$file, 'php://memory', 'php://temp', 'null://x', 'data:,abc'] as $url) {
    $f = fopen($url, 'r', false, $context);
    echo basename($url), ": ";
    var_dump(stream_context_get_options($f));
    fclose($f);
}

$f = fopen($file, 'r', false, $context);
stream_context_set_option($f, 'demo', 'b', 2);
var_dump(stream_context_get_options($context));
fclose($f);

// opened without a context, or with the default one, a stream has its own
$f = fopen($file, 'r');
var_dump(stream_context_get_options($f));
fclose($f);
$default = stream_context_get_default(['demo' => ['c' => 3]]);
$f = fopen($file, 'r', false, $default);
stream_context_set_option($f, 'demo', 'd', 4);
var_dump(stream_context_get_options($f));
var_dump(stream_context_get_options($default));
fclose($f);
unlink($file);
