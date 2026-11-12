<?php
// disable_functions removes the named functions; exit and die can't be

$file = tempnam(sys_get_temp_dir(), 'df');
file_put_contents($file, <<<'PHP'
<?php
var_dump(function_exists('strrev'), function_exists('strlen'));
try {
    strrev('abc');
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
echo strlen('abc'), "\n";
$f = new SplFileObject(__FILE__);
var_dump(is_array($f->fstat()), function_exists('fstat'));
PHP);
foreach (['strrev', 'STRREV', 'strlen,,strrev  ucfirst', 'fstat'] as $list) {
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d ' . escapeshellarg("disable_functions=$list") . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace($file, 'FILE', $out);
}
unlink($file);
