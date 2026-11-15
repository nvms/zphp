<?php
// debug_backtrace() and debug_print_backtrace() list eval() and include as
// the calls that ran the code, with no frame of their own for the code

function show(): void {
    ob_start();
    debug_print_backtrace();
    $printed = ob_get_clean();
    echo str_replace([__DIR__, DIRECTORY_SEPARATOR], ['DIR', '/'], $printed);
    foreach (debug_backtrace() as $frame) {
        $args = isset($frame['args']) ? count($frame['args']) : '-';
        echo '  ', $frame['function'], ' line ', $frame['line'] ?? '-', ' args ', $args, ' keys ', implode(',', array_keys($frame)), "\n";
    }
}

eval('show();');
function inner() {
    eval('show();');
}
inner();

$file = __DIR__ . '/backtrace_include_eval.inc';
file_put_contents($file, '<?php show(); eval("show();"); ' . "\n" . 'echo str_replace([__DIR__, DIRECTORY_SEPARATOR], ["DIR", "/"], json_encode(debug_backtrace(DEBUG_BACKTRACE_IGNORE_ARGS))), "\n"; return 1;');
include $file;
function viaInclude() {
    require $file = __DIR__ . '/backtrace_include_eval.inc';
}
viaInclude();
unlink($file);
