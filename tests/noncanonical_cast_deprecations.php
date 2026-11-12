<?php
// php 8.5 deprecates the long cast spellings and the backtick operator while
// compiling, even in code that never runs

$file = tempnam(sys_get_temp_dir(), 'casts');
file_put_contents($file, <<<'PHP'
<?php
var_dump((integer) "1", (DOUBLE) 2, (binary) 3, (Boolean) 0);
var_dump((int) "1", (float) 2, (string) 3, (bool) 0);
$z = 0 && (double) $q;
if (false) {
    $x = (integer) $y;
    echo `true`;
}
PHP);
$out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d error_reporting=-1 ' . escapeshellarg($file) . ' 2>&1');
echo str_replace($file, 'FILE', $out);
unlink($file);
