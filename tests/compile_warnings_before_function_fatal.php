<?php
// warnings a function's body raised while compiling are raised before the
// compile error that stops the file, as php raised them by then
$file = sys_get_temp_dir() . '/zphp_compile_notes_' . getmypid() . '.php';
file_put_contents($file, '<?php
function foo(): never {
    try {
        throw new Exception("bad");
    } finally {
        return;
    }
}
');
$out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d log_errors=0 -d error_reporting=-1 -d fatal_error_backtraces=0 ' . escapeshellarg($file) . ' 2>&1');
echo str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'FILE', $out);
unlink($file);
