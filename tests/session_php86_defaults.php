<?php
// php 8.6 turned on session.use_strict_mode and session.cookie_httponly and
// made session.cookie_samesite Lax; strict mode refuses an id with no data
ob_start();
foreach (['session.use_strict_mode', 'session.cookie_httponly', 'session.cookie_samesite'] as $name) {
    var_dump(ini_get($name));
}
$params = session_get_cookie_params();
var_dump($params['httponly'], $params['samesite']);
$dir = sys_get_temp_dir() . '/zphp_sess_strict_' . getmypid();
@mkdir($dir);
session_save_path($dir);
ini_set('session.use_cookies', '0');
session_id('unknownid0123456789');
session_start();
var_dump(session_id() === 'unknownid0123456789', strlen(session_id()) > 0);
$_SESSION['x'] = 1;
$kept = session_id();
session_write_close();
// an id the handler has data for is kept
session_id($kept);
session_start();
var_dump(session_id() === $kept, $_SESSION['x']);
session_destroy();
// with strict mode off, any id is adopted
ini_set('session.use_strict_mode', '0');
session_id('unknownid0123456789');
session_start();
var_dump(session_id());
// an empty session encodes to "" (it was false)
var_dump(session_encode());
session_destroy();
array_map('unlink', glob("$dir/*") ?: []);
rmdir($dir);
