<?php
// php_strip_whitespace(), and highlight_file()/highlight_string() returning
// a string, capture through an output buffer, which a running output handler
// may not start: php ends the script with a fatal error

$calls = [
    'php_strip_whitespace(__FILE__)',
    'highlight_string("<?php 1;", true)',
    'highlight_file(__FILE__, true)',
    'highlight_string("<?php 1;")',
];
$file = sys_get_temp_dir() . '/zphp_ob_lock_' . getmypid() . '.php';
foreach ($calls as $call) {
    file_put_contents($file, "<?php\nob_start(function (\$b) { \$s = $call; return strtoupper(\$b); });\necho \"a\\n\";\nob_end_flush();\necho \"after\\n\";\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d fatal_error_backtraces=0 ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'FILE', $out), "\n";
}
unlink($file);
