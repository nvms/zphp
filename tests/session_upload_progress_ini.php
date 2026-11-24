<?php
// session.upload_progress.enabled is off by default; while it is on, the
// session's settings can't be changed at run time, by ini_set(),
// ini_restore() or the session functions that set them

var_dump(ini_get('session.upload_progress.enabled'));
// PHP_INI_PERDIR settings are refused at run time
var_dump(ini_set('session.upload_progress.enabled', '1'));
var_dump(ini_set('session.auto_start', '1'));
var_dump(ini_get('session.upload_progress.enabled'));

$child = <<<'PHP'
<?php
ob_start();
function attempt(string $what, callable $f): void {
    try {
        $r = $f();
        echo "$what: ", var_export($r, true), "\n";
    } catch (Throwable $e) {
        echo "$what: ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}
attempt('enabled', fn() => ini_get('session.upload_progress.enabled'));
attempt('restore unmodified', fn() => ini_restore('session.name'));
attempt('set name', fn() => ini_set('session.name', 'OTHER'));
attempt('name', fn() => ini_get('session.name'));
attempt('restore after a refused set', fn() => ini_restore('session.name'));
attempt('set gc_probability', fn() => ini_set('session.gc_probability', '5'));
attempt('set use_only_cookies off', fn() => ini_set('session.use_only_cookies', '0'));
attempt('set serialize_handler', fn() => ini_set('session.serialize_handler', 'php_serialize'));
attempt('set sid_length', fn() => ini_set('session.sid_length', '40'));
attempt('set lazy_write', fn() => ini_set('session.lazy_write', '0'));
attempt('set upload_progress.name', fn() => ini_set('session.upload_progress.name', 'x'));
attempt('set auto_start', fn() => ini_set('session.auto_start', '1'));
attempt('set encode_sources', fn() => ini_set('session.encode_sources', 'globals'));
attempt('set precision', fn() => ini_set('precision', '10'));
attempt('cookie_lifetime', fn() => ini_get('session.cookie_lifetime'));
// the session functions that set a setting are refused the same way
if (ini_get('session.upload_progress.enabled')) {
    attempt('session_name()', fn() => session_name());
    attempt('session_name(x)', fn() => session_name('abc'));
    attempt('session_save_path(x)', fn() => is_string(session_save_path(sys_get_temp_dir())));
    attempt('session_set_cookie_params', fn() => session_set_cookie_params(5));
    attempt('session_cache_limiter(x)', fn() => session_cache_limiter('public'));
    attempt('session_cache_expire(x)', fn() => session_cache_expire(5));
    attempt('session_module_name(x)', fn() => session_module_name('files'));
}
attempt('started', fn() => session_status() === PHP_SESSION_NONE);
echo "done\n";
PHP;

$file = tempnam(sys_get_temp_dir(), 'upl');
file_put_contents($file, $child);
$php = escapeshellarg(PHP_BINARY);
foreach (['1', 'On', '0'] as $setting) {
    echo "-- upload progress $setting\n";
    echo shell_exec("$php -n -d error_reporting=24575 -d session.upload_progress.enabled=$setting -d session.cookie_lifetime=42 " . escapeshellarg($file));
}
unlink($file);
