<?php
// php decides `0 && x` and `1 || x` while compiling and never compiles x, so
// nothing in it is checked or reported

$file = tempnam(sys_get_temp_dir(), 'sc');
file_put_contents($file, <<<'PHP'
<?php
var_dump(0 && (function (int $a = null) { return 1; }));
var_dump(true || (fn(int $b = null) => 2));
var_dump('' && print "never\n");
var_dump('a' || print "never\n");
var_dump(1 && (function (int $c = null) { return 3; }) !== null);
PHP);
$out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d error_reporting=-1 ' . escapeshellarg($file) . ' 2>&1');
echo str_replace($file, 'FILE', $out);
unlink($file);
