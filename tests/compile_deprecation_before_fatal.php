<?php
// a deprecation raised while compiling is reported even when a compile
// error later in the file stops the script; one after the error is not

$file = sys_get_temp_dir() . '/zphp_compile_notes_' . getmypid() . '.php';
file_put_contents($file, <<<'PHP'
<?php
interface _ {}

class _x {
    function f(?int $a = null, $b) {}
}

class bool {}

function g($a = 1, $b) {}
echo "unreachable\n";
PHP);

foreach (['E_ALL', 'E_ALL & ~E_DEPRECATED'] as $level) {
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d log_errors=0 -d ' . escapeshellarg("error_reporting=$level") . ' ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace($file, 'FILE', $out), "\n";
}
unlink($file);
