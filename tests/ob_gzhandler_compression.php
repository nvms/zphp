<?php
// zlib output compression: ob_gzhandler, zlib.output_compression and
// ob_gzhandler() compress for a request whose Accept-Encoding names gzip or
// deflate. each case runs in a child, which has its own request
$dir = sys_get_temp_dir() . '/zphp-gz-' . getmypid();
@mkdir($dir);
$run = function (string $name, string $code, string $accept, string $flags = '') use ($dir) {
    $file = "$dir/$name.php";
    file_put_contents($file, "<?php\n" . $code);
    echo "-- $name ($accept) $flags\n";
    $cmd = escapeshellarg(PHP_BINARY) . " -d display_errors=stderr -d log_errors=0 $flags " . escapeshellarg($file);
    $proc = proc_open($cmd, [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes, null, ['HTTP_ACCEPT_ENCODING' => $accept] + getenv());
    $out = stream_get_contents($pipes[1]);
    $err = stream_get_contents($pipes[2]);
    proc_close($proc);
    if (str_starts_with($out, "\x1f\x8b")) {
        echo "gzip: ", bin2hex(substr($out, 0, 10)), "\n", gzdecode($out), "\n";
    } elseif ($accept === 'deflate' && $out !== '' && ($raw = @gzuncompress($out)) !== false) {
        echo "deflate:\n", $raw, "\n";
    } else {
        echo "plain:\n", $out, "\n";
    }
    echo str_replace($file, 'FILE', $err);
};

$handler = <<<'PHP'
var_dump(zlib_get_coding_type());
var_dump(ob_start('ob_gzhandler'));
var_dump(zlib_get_coding_type(), ob_list_handlers());
echo str_repeat("compress me ", 20);
PHP;
$run('handler', $handler, 'gzip, deflate');
$run('handler', $handler, 'deflate');
$run('handler', $handler, 'identity');
$run('handler', $handler, 'gzip', '-d zlib.output_compression=1');

$twice = <<<'PHP'
ob_start('ob_gzhandler');
var_dump(ob_start('ob_gzhandler'));
var_dump(ob_start('ob_gzhandler', 0, PHP_OUTPUT_HANDLER_STDFLAGS));
echo "inner\n";
ob_start();
echo "nested\n";
ob_end_flush();
$s = ob_get_status(true);
var_dump(count($s), $s[0]['name'], $s[0]['chunk_size']);
PHP;
$run('twice', $twice, 'gzip');

// output already went out: the handler can't send its headers and passes
// the output along
$late = <<<'PHP'
echo "first\n";
ob_start('ob_gzhandler');
echo "second\n";
ob_end_flush();
var_dump(ini_set('zlib.output_compression', '1'));
PHP;
$run('late', $late, 'gzip');

$runtime = <<<'PHP'
var_dump(ini_set('zlib.output_compression', '4096') !== false);
var_dump(ob_list_handlers(), ob_get_status()['chunk_size']);
echo str_repeat("abc", 3000), "\n";
PHP;
$run('runtime', $runtime, 'gzip');

$clean = <<<'PHP'
ob_start('ob_gzhandler');
echo "discarded";
ob_clean();
echo "kept\n";
ob_end_clean();
echo "after\n";
PHP;
$run('clean', $clean, 'gzip');

$direct = <<<'PHP'
var_dump(bin2hex(ob_gzhandler("abc", PHP_OUTPUT_HANDLER_START | PHP_OUTPUT_HANDLER_FINAL)));
var_dump(bin2hex(ob_gzhandler("abc", PHP_OUTPUT_HANDLER_START)));
var_dump(bin2hex(ob_gzhandler("def", PHP_OUTPUT_HANDLER_FLUSH)));
var_dump(bin2hex(ob_gzhandler("ghi", PHP_OUTPUT_HANDLER_FINAL)));
var_dump(ob_gzhandler("ghi", PHP_OUTPUT_HANDLER_FINAL));
var_dump(zlib_get_coding_type());
PHP;
$run('direct', $direct, 'gzip');
$run('direct', $direct, 'none');

$chunked = <<<'PHP'
ob_start('ob_gzhandler', 64);
for ($i = 0; $i < 10; $i++) echo str_repeat(chr(65 + $i), 30), "\n";
PHP;
$run('chunked', $chunked, 'gzip');

foreach (glob("$dir/*.php") as $f) unlink($f);
rmdir($dir);
