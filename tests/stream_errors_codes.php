<?php
// the StreamErrorCode, wrapper name, severity and terminating flag of the
// errors common stream operations raise, stored for stream_last_errors()
$dir = sys_get_temp_dir() . '/zphp_stream_errors_codes';
@mkdir($dir);
$ro = "$dir/ro.txt";
file_put_contents($ro, "data");
$ctx = stream_context_create(['stream' => ['error_mode' => StreamErrorMode::Silent, 'error_store' => StreamErrorStore::All]]);

function show($label, $r) {
    echo "== $label: ", var_export($r, true), "\n";
    foreach (stream_last_errors() as $e) {
        echo "  ", $e->code->name, " [", $e->wrapperName, "] sev=", $e->severity, " term=", var_export($e->terminating, true), " ", str_replace(sys_get_temp_dir(), 'TMP', $e->message), "\n";
    }
    stream_clear_errors();
}

class W {
    public $context;
    function stream_open($p, $m, $o, &$op) { return true; }
    function stream_read($n) { return str_repeat('x', $n + 2); }
    function stream_eof() { return 5; }
}
class Bare { public $context; }
class Failing { public $context; function stream_open($p, $m, $o, &$op) { return false; } function url_stat($p, $f) { return false; } }
stream_wrapper_register('ww', 'W');
stream_wrapper_register('bare', 'Bare');
stream_wrapper_register('failing', 'Failing');

show('fopen missing', fopen("$dir/missing.txt", 'r', false, $ctx));
show('fopen dir for write', fopen($dir, 'w', false, $ctx));
show('fopen bad mode', fopen($ro, 'z', false, $ctx));
show('file_get_contents missing', file_get_contents("$dir/missing.txt", false, $ctx));
show('file_get_contents dir', file_get_contents($dir, false, $ctx));
show('file missing', file("$dir/missing.txt", 0, $ctx));
show('readfile missing', readfile("$dir/missing.txt", false, $ctx));
show('file_put_contents into missing dir', file_put_contents("$dir/no/such.txt", "x", 0, $ctx));
show('copy missing', copy("$dir/missing.txt", "$dir/x.txt", $ctx));
show('unlink missing', unlink("$dir/missing.txt", $ctx));
show('rename missing', rename("$dir/missing.txt", "$dir/x.txt", $ctx));
show('mkdir existing', mkdir($dir, 0777, false, $ctx));
show('mkdir recursive existing', mkdir($dir, 0777, true, $ctx));
show('rmdir missing', rmdir("$dir/missing", $ctx));
show('opendir missing', opendir("$dir/missing", $ctx));
show('scandir missing', scandir("$dir/missing", 0, $ctx));
show('unknown wrapper', fopen('nowrapper://foo', 'r', false, $ctx));
show('remote file', fopen('file://host/foo', 'r', false, $ctx));
show('php invalid', fopen('php://nope', 'r', false, $ctx));
show('php fd invalid', fopen('php://fd/x', 'r', false, $ctx));
show('filter missing', fopen("php://filter/read=nope/resource=$ro", 'r', false, $ctx));
show('filter missing resource', fopen("php://filter/read=string.rot13/resource=$dir/missing.txt", 'r', false, $ctx));
show('data bad', fopen('data:text/plain;foo', 'r', false, $ctx));
show('bare open', fopen('bare://x', 'r', false, $ctx));
show('failing open', fopen('failing://x', 'r', false, $ctx));
show('bare opendir', opendir('bare://x', $ctx));
show('bare unlink', unlink('bare://x', $ctx));
show('bare rename', rename('bare://x', 'bare://y', $ctx));
show('bare mkdir', mkdir('bare://x', 0777, false, $ctx));
show('bare rmdir', rmdir('bare://x', $ctx));
$f = fopen('ww://x', 'r', false, $ctx);
show('user read excess', fread($f, 3));
show('user eof type', feof($f));
show('user write missing', fwrite($f, "abc"));
show('user stat missing', fstat($f));
show('user seek missing', fseek($f, 10));
show('user tell', ftell($f));
show('user truncate', ftruncate($f, 0));
show('user lock', flock($f, LOCK_SH));
show('user set option', stream_set_blocking($f, true));
show('user meta', stream_get_meta_data($f)['eof']);
fclose($f);
$f = fopen($ro, 'r', false, $ctx);
show('write read-only', fwrite($f, "abc"));
fclose($f);
$f = fopen("$dir/wo.txt", 'w', false, $ctx);
show('read write-only', fread($f, 10));
fclose($f);
$f = fopen('php://memory', 'r', false, $ctx);
show('memory write readonly', fwrite($f, "abc"));
fclose($f);
$f = fopen('php://output', 'w', false, $ctx);
show('seek output', fseek($f, 10));
fclose($f);
show('register existing', stream_wrapper_register('ww', 'W'));
show('unregister missing', stream_wrapper_unregister('nope'));
show('restore missing', stream_wrapper_restore('nope'));
show('restore unchanged', stream_wrapper_restore('file'));
show('stat missing', @stat("$dir/missing.txt"));
show('failing stat', @stat('failing://x'));
unlink($ro);
@unlink("$dir/wo.txt");
@rmdir($dir);
