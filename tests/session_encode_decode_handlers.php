<?php
// session_encode/session_decode with php's three serializers, and decoding
// malformed data, which destroys the session

ob_start();
ini_set('session.save_path', sys_get_temp_dir());
ini_set('session.use_cookies', '0');
$log = [];
set_error_handler(function ($n, $s) use (&$log) {
    $log[] = "[$n] " . str_replace([__FILE__, str_replace('/', DIRECTORY_SEPARATOR, __FILE__)], 'FILE', $s);
    return true;
});

$log[] = var_export(session_decode("a|i:1;"), true);
$log[] = var_export(session_encode(), true);

$exception = 'O:9:"Exception":2:{s:7:"' . "\0" . '*' . "\0" . 'file";s:0:"";}';
foreach (['php', 'php_serialize', 'php_binary'] as $handler) {
    ini_set('session.serialize_handler', $handler);
    $log[] = "== $handler";
    $samples = [
        'php' => ["a|i:1;b|s:1:\"x\";", "abc", "a|i:1;b", "a|i:1;b|x", "a|s:3:\"ab", "", "a|i:1;", "r|a:1:{i:0;i:7;}s|R:2;", $exception],
        'php_serialize' => ["a:1:{s:1:\"k\";i:5;}", "a:1:{", "i:5;", "", "N;", $exception],
        'php_binary' => ["\x01ai:1;\x02bbs:1:\"y\";", "\x05ab", "\x01a", ""],
    ][$handler];
    foreach ($samples as $data) {
        session_start();
        $r = session_decode($data);
        $log[] = json_encode($data) . ' ' . var_export($r, true) . ' ' . json_encode($_SESSION) . ' ' . session_status();
    }
    session_start();
    $_SESSION = ['name' => 'value', 'list' => [1, 2], 'obj' => new ArrayObject([3])];
    $log[] = json_encode(session_encode());
    $_SESSION[7] = 'numeric';
    $log[] = json_encode(session_encode());
    $_SESSION = ['bad|key' => 1];
    $log[] = var_export(session_encode(), true);
    $_SESSION = [];
    session_destroy();
}
$log[] = var_export(session_destroy(), true);
ob_end_clean();
echo implode("\n", $log), "\n";
