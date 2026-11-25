<?php
// each error mode and store over the errors of common stream operations
$dir = sys_get_temp_dir() . '/zphp_stream_errors_operations';
@mkdir($dir);
$ro = "$dir/ro.txt";
file_put_contents($ro, "data");

class W {
    public $context;
    function stream_open($p, $m, $o, &$op) { return true; }
    function stream_read($n) { return str_repeat('x', $n + 2); }
    function stream_eof() { return true; }
}
stream_wrapper_register('ww', 'W');

$contexts = [
    'error+handler' => stream_context_create(['stream' => ['error_mode' => StreamErrorMode::Error, 'error_handler' => function ($errors) { echo "handler: ", count($errors), " ", $errors[0]->code->name, "\n"; }]]),
    'exception' => stream_context_create(['stream' => ['error_mode' => StreamErrorMode::Exception]]),
    'exception store all' => stream_context_create(['stream' => ['error_mode' => StreamErrorMode::Exception, 'error_store' => StreamErrorStore::All]]),
    'silent terminating' => stream_context_create(['stream' => ['error_mode' => StreamErrorMode::Silent, 'error_store' => StreamErrorStore::Terminating]]),
];
foreach ($contexts as $name => $ctx) {
    echo "##### $name\n";
    stream_clear_errors();
    $ops = [
        'fopen missing' => fn() => fopen("$dir/missing", 'r', false, $ctx),
        'unlink missing' => fn() => unlink("$dir/missing", $ctx),
        'mkdir existing' => fn() => mkdir($dir, 0777, false, $ctx),
        'filter missing' => fn() => fopen("php://filter/read=nope|string.rot13/resource=$ro", 'r', false, $ctx),
        'user read' => function () use ($ctx) { $f = fopen('ww://x', 'r', false, $ctx); return fread($f, 4); },
        'remote' => fn() => file_get_contents('file://elsewhere/x', false, $ctx),
    ];
    foreach ($ops as $label => $op) {
        echo "-- $label\n";
        try {
            var_dump($op());
        } catch (StreamException $e) {
            echo get_class($e), ": ", str_replace($dir, 'DIR', $e->getMessage()), " (", $e->getCode(), ") line ", $e->getLine(), "\n";
            foreach ($e->getErrors() as $err) echo "  ", $err->code->name, " ", $err->wrapperName, "\n";
            var_dump($e->getPrevious());
        }
        foreach (stream_last_errors() as $err) echo "  stored: ", $err->code->name, "\n";
    }
}
// a handler that isn't callable
$bad = stream_context_create(['stream' => ['error_handler' => 'no_such_function']]);
try {
    fopen("$dir/missing", 'r', false, $bad);
} catch (TypeError $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
// the handler sees the errors as StreamError objects
$dump = stream_context_create(['stream' => ['error_mode' => StreamErrorMode::Silent, 'error_handler' => function ($errors) { var_dump($errors); }]]);
@fopen("$dir/missing", 'r', false, $dump);
// a stream's own context reports its operations
$ctx = stream_context_create(['stream' => ['error_mode' => StreamErrorMode::Exception]]);
$f = fopen($ro, 'r', false, $ctx);
try {
    fwrite($f, "x");
    echo "no exception for a notice\n";
    fseek($f, -5);
    echo "fseek: no exception\n";
} catch (StreamException $e) {
    echo $e->getMessage(), "\n";
}
fclose($f);
var_dump(count(stream_last_errors()));
unlink($ro);
rmdir($dir);
