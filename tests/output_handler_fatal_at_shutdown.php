<?php
// a fatal error inside an output handler flushed at shutdown deactivates the
// output layer and is still displayed; an uncaught exception there is lost
// with the buffers
$cases = [
    'fatal' => '<?php function obh($s) { return ob_get_flush(); } ob_start("obh"); echo "foo\n";',
    'nested start' => '<?php ob_start(function ($s) { ob_start(); return $s; }); echo "bar\n";',
    'exception' => '<?php ob_start(function ($s) { throw new Exception("x"); }); echo "baz\n";',
];
$file = sys_get_temp_dir() . '/zphp-obfatal-' . getmypid() . '.php';
foreach ($cases as $name => $code) {
    file_put_contents($file, $code);
    $cmd = escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d fatal_error_backtraces=0 -d html_errors=0 ' . escapeshellarg($file);
    exec($cmd, $out, $status);
    echo "-- $name ($status)\n", str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'FILE', implode("\n", $out)), "\n";
    $out = [];
}
unlink($file);
