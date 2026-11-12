<?php
// stream contexts: options, params, the default context, and user
// wrappers that see the context they were opened with

set_error_handler(function ($no, $msg) { echo "error $no: $msg\n"; return true; });

try {
    stream_context_create([], ['notification' => null]);
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
$ctx = stream_context_create(['http' => ['method' => 'POST', 'header' => 'X-A: 1']]);
var_dump(stream_context_get_options($ctx));
var_dump(stream_context_get_params($ctx));

var_dump(stream_context_set_option($ctx, 'http', 'timeout', 5));
var_dump(stream_context_set_option($ctx, ['ftp' => ['overwrite' => true], 'http' => ['method' => 'PUT']]));
var_dump(stream_context_get_options($ctx));

try {
    stream_context_set_option($ctx, 'http');
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    stream_context_set_option($ctx, ['http' => []], 'x');
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    stream_context_create(['http' => 'nope']);
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    stream_context_create([['a' => 1]]);
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}

var_dump(stream_context_set_params($ctx, ['options' => ['ssl' => ['verify_peer' => false]]]));
var_dump(stream_context_get_options($ctx)['ssl']);
try {
    stream_context_set_params($ctx, ['notification' => 'no_such_function']);
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
var_dump(stream_context_set_params($ctx, ['notification' => 'strlen']));
var_dump(stream_context_get_params($ctx)['notification']);

$def = stream_context_get_default();
var_dump(stream_context_get_options($def));
$def2 = stream_context_get_default(['http' => ['user_agent' => 'zz']]);
var_dump($def === $def2);
var_dump(stream_context_get_options(stream_context_get_default()));
stream_context_set_default(['http' => ['max_redirects' => 2]]);
var_dump(stream_context_get_options(stream_context_get_default()));

$f = fopen(__FILE__, 'r');
var_dump(stream_context_get_options($f));
var_dump(stream_context_set_option($f, 'file', 'x', 1));
var_dump(stream_context_get_options($f));
fclose($f);

class W {
    public $context;
    function stream_open($path, $mode, $options, &$opened) {
        var_dump(is_resource($this->context));
        var_dump(stream_context_get_options($this->context));
        return true;
    }
    function stream_read($n) { return ''; }
    function stream_eof() { return true; }
    function stream_stat() { return []; }
}
stream_wrapper_register('w', 'W');
file_get_contents('w://a', false, stream_context_create(['w' => ['k' => 'v']]));

class Typed {
    public int $context;
    function stream_open($path, $mode, $options, &$opened) { return true; }
}
stream_wrapper_register('typed', 'Typed');
try {
    fopen('typed://a', 'r', false, stream_context_create());
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
