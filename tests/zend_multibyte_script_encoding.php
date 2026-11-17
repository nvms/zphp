<?php
// zend.multibyte: a script's byte order mark or its wide characters name its
// encoding, and the script is converted to the internal encoding before it
// is read; an unknown zend.script_encoding is warned about at startup
$dir = sys_get_temp_dir() . '/zphp_multibyte_' . getmypid();
@mkdir($dir);

function utf16le(string $s): string {
    return implode('', array_map(fn($c) => $c . "\0", str_split($s)));
}

file_put_contents("$dir/bom8.php", "\xEF\xBB\xBF<?php\nprint \"Hello World\\n\";\n");
file_put_contents("$dir/bom16.php", "\xFF\xFE" . utf16le("<?php\nprint \"caf\xE9\\n\";\n?>\nafter\n") . "\n");
file_put_contents("$dir/wide.php", utf16le("<?php echo strlen('wide'), \"\\n\";"));
file_put_contents("$dir/include16.php", '<?php include __DIR__ . "/wide.php"; echo "included\n";');
file_put_contents("$dir/plain.php", "<?php echo 'plain', \"\\n\";");

// no ini file, with mbstring, whose functions zend.multibyte converts with
$base = escapeshellarg(PHP_BINARY) . ' -n';
if (trim(shell_exec($base . ' -r ' . escapeshellarg('echo (int) extension_loaded("mbstring");'))) !== '1') $base .= ' -d extension=mbstring';

function run($dir, $ini, $script) {
    global $base;
    $cmd = $base . ' -d display_errors=1 -d log_errors=0 -d error_reporting=-1';
    foreach ($ini as $k => $v) $cmd .= ' -d ' . escapeshellarg("$k=$v");
    $cmd .= ' ' . escapeshellarg("$dir/$script") . ' 2>&1';
    exec($cmd, $out, $status);
    echo $script, ': ', bin2hex(implode("\n", $out)), " [status $status]\n";
}

$latin1 = ['zend.multibyte' => 1, 'internal_encoding' => 'iso-8859-1'];
$utf8 = ['zend.multibyte' => 1, 'internal_encoding' => 'UTF-8'];
run($dir, $latin1, 'bom8.php');
run($dir, $latin1, 'bom16.php');
run($dir, $utf8, 'bom16.php');
run($dir, $utf8, 'include16.php');
run($dir, $utf8 + ['zend.detect_unicode' => 0], 'bom8.php');
run($dir, $utf8 + ['zend.script_encoding' => 'pass'], 'plain.php');
run($dir, $utf8 + ['zend.script_encoding' => 'UTF-16LE'], 'wide.php');

foreach (glob("$dir/*") as $f) unlink($f);
rmdir($dir);
