<?php
// zend.multibyte with a Shift_JIS script: its second bytes may be a
// backslash, so it is read as UTF-8 and its string literals are converted
// back to the internal encoding (or left in UTF-8 when that is internal)
$dir = sys_get_temp_dir() . '/zphp_sjis_' . getmypid();
@mkdir($dir);

// 表示 (hyou-ji), whose first character ends in 0x5c, as a function name, a
// parameter name and in literals
$func = "\x95\x5c\x8e\xa6";
$param = "\x88\xf8\x90\x94";
$text = "\x83\x68\x83\x8c\x83\x7e\x83\x74\x83\x40\x83\x5c";
file_put_contents("$dir/names.php", "<?php\nfunction $func(\$$param) {\n    echo \$$param;\n}\n$func(\"$text\");\necho '|', '$text', '|';\n");
file_put_contents("$dir/declared.php", "<?php\ndeclare(encoding='Shift_JIS');\n\$s = \"\x95\x5c\";\nprintf('%x:%x:%d', ord(\$s[0]), ord(\$s[1]), strlen(\$s));\n");

$base = escapeshellarg(PHP_BINARY) . ' -n';
if (trim(shell_exec($base . ' -r ' . escapeshellarg("echo (int) extension_loaded('mbstring');"))) !== '1') $base .= ' -d extension=mbstring';

function run($dir, $ini, $script) {
    global $base;
    $cmd = $base . ' -d display_errors=1 -d log_errors=0 -d error_reporting=-1';
    foreach ($ini as $k => $v) $cmd .= ' -d ' . escapeshellarg("$k=$v");
    $cmd .= ' ' . escapeshellarg("$dir/$script") . ' 2>&1';
    exec($cmd, $out, $status);
    echo $script, ': ', bin2hex(implode("\n", $out)), " [status $status]\n";
}

$sjis = ['zend.multibyte' => 1, 'zend.script_encoding' => 'Shift_JIS', 'internal_encoding' => 'Shift_JIS'];
run($dir, $sjis, 'names.php');
run($dir, ['internal_encoding' => 'UTF-8'] + $sjis, 'names.php');
run($dir, ['zend.multibyte' => 1, 'internal_encoding' => 'SJIS'], 'declared.php');

foreach (glob("$dir/*") as $f) unlink($f);
rmdir($dir);
