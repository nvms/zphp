<?php
// output buffering as php's output layer runs it: handler names and status,
// the flags a level is started with, chunked buffers, handlers that fail or
// print, and the buffers still open at the end of the script
set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});

function upper($buffer, $phase) {
    return strtoupper($buffer);
}
class H {
    public static function wrap($buffer) {
        return "<$buffer>";
    }
    public function __invoke($buffer) {
        return $buffer;
    }
}

ob_start();
ob_start('upper');
ob_start(['H', 'wrap']);
ob_start(new H);
ob_start(fn ($b) => $b);
$names = ob_list_handlers();
$status = ob_get_status(true);
ob_end_flush();
ob_end_flush();
ob_end_flush();
ob_end_flush();
$top = ob_get_status();
ob_end_clean();
foreach ($names as $name) echo preg_replace('/:\d+\}$/', ':N}', str_replace(__FILE__, 'FILE', $name)), "\n";
foreach ($status as $s) echo $s['level'], ' ', $s['type'], ' ', $s['flags'], ' ', $s['chunk_size'], ' ', $s['buffer_size'], ' ', $s['buffer_used'], "\n";
echo $top['name'], ' ', $top['flags'], "\n";

// the notices for operations with no buffer, and a level that refuses them
var_dump(ob_flush(), ob_clean(), ob_end_flush(), ob_end_clean(), ob_get_clean(), ob_get_flush());
ob_start(null, 0, 0);
echo "kept";
var_dump(ob_flush(), ob_clean(), ob_end_flush(), ob_end_clean());
$level = ob_get_level();
$contents = ob_get_contents();
// only php_output_end_all at shutdown removes it; flush its bytes here by
// copying them out instead
echo "\n";
$kept = ob_get_status();

// invalid handlers
var_dump(ob_start('no_such_function'));
var_dump(ob_start(['H', 'missing']));
var_dump(ob_start([1, 2, 3]));

// chunk_size runs the handler as the buffer fills
$log = [];
ob_start(function ($b, $phase) use (&$log) {
    $log[] = "$phase:" . strlen($b);
    return $b;
}, 4);
echo "ab";
echo "cdef";
echo "g";
ob_end_flush();

// a handler that returns false is disabled and passes its input on
ob_start(function ($b) {
    return false;
});
echo "raw ";
ob_end_flush();
echo "\n";

// a handler that prints: its output is dropped, with a deprecation
ob_start(function ($b) {
    echo "lost";
    return "[$b]";
});
echo "x";
ob_end_flush();
echo "\n";

restore_error_handler();
echo "level $level, contents ", var_export($contents, true), ", flags ", $kept['flags'], "\n";
print_r($log);

// left open: flushed through the handler after the shutdown functions
register_shutdown_function(function () {
    echo "shutdown\n";
});
ob_start('upper');
echo "end of script\n";
