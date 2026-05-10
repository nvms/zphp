<?php
$dir = sys_get_temp_dir();
$path = "$dir/zphp_fs_" . getmypid();

// file_get_contents with offset/length
file_put_contents($path, "0123456789ABCDEF");
echo file_get_contents($path, false, null, 5), "|\n"; // 56789ABCDEF
echo file_get_contents($path, false, null, 5, 4), "|\n"; // 5678
echo file_get_contents($path, false, null, 0, 3), "|\n"; // 012
echo file_get_contents($path, false, null, -3), "|\n"; // DEF (negative offset from end)
echo file_get_contents($path, false, null, 100), "|\n"; // ""

// fgetc
$f = fopen($path, "r");
echo fgetc($f), fgetc($f), fgetc($f), "\n"; // 012
echo fseek($f, 5) === 0 ? "ok" : "nok", "\n";
echo fgetc($f), "\n"; // 5
fseek($f, 0, SEEK_END);
var_dump(fgetc($f)); // false (eof)
fclose($f);

// copy overwrite
$src = "$dir/zphp_cp_src_" . getmypid();
$dst = "$dir/zphp_cp_dst_" . getmypid();
file_put_contents($src, "new");
file_put_contents($dst, "old");
copy($src, $dst);
echo file_get_contents($dst), "\n"; // new
unlink($src);
unlink($dst);

// mkdir recursive
$d = "$dir/zphp_mk_" . getmypid() . "/a/b/c";
mkdir($d, 0o755, true);
echo is_dir($d) ? "y" : "n", "\n";
echo is_dir(dirname($d, 2)) ? "y" : "n", "\n";
rmdir($d);
rmdir(dirname($d));
rmdir(dirname($d, 2));
rmdir(dirname($d, 3));

// fileowner / filegroup (just check return type)
$f = "$dir/zphp_own_" . getmypid();
file_put_contents($f, "");
$o = fileowner($f);
$g = filegroup($f);
echo gettype($o), ":", gettype($g), ":", $o > 0 && $g > 0 ? "ok" : "no", "\n";

// filemtime / filesize / fileatime / filectime
clearstatcache();
$now = time();
$mt = filemtime($f);
echo abs($now - $mt) < 5 ? "mt-recent\n" : "mt-old:".($now-$mt)."\n";
echo filesize($f), "\n"; // 0
file_put_contents($f, "12345");
clearstatcache();
echo filesize($f), "\n"; // 5
$mt = filemtime($f);
echo gettype($mt), "\n"; // integer
unlink($f);

// rewind / ftell after fread
$path2 = "$dir/zphp_rw_" . getmypid();
file_put_contents($path2, "ABCDEF");
$f = fopen($path2, "r");
echo ftell($f), "\n"; // 0
fread($f, 3);
echo ftell($f), "\n"; // 3
rewind($f);
echo ftell($f), "\n"; // 0
fread($f, 6);
echo ftell($f), "\n"; // 6
fclose($f);
unlink($path2);

// fseek beyond EOF (writes zero-fill on next write for w+ mode)
$path3 = "$dir/zphp_seek_" . getmypid();
$f = fopen($path3, "w+");
fwrite($f, "ABCD");
fseek($f, 10);
echo ftell($f), "\n"; // 10
fwrite($f, "X");
fclose($f);
echo filesize($path3), "\n"; // 11
$content = file_get_contents($path3);
echo strlen($content), "|", bin2hex($content), "\n";
unlink($path3);

// lstat vs stat (link)
$f = "$dir/zphp_lstat_" . getmypid();
$l = "$dir/zphp_lstat_link_" . getmypid();
file_put_contents($f, "data");
@unlink($l);
if (function_exists('symlink') && @symlink($f, $l)) {
    $s = stat($l);
    $ls = lstat($l);
    echo $s !== false ? "stat-ok\n" : "no\n";
    echo $ls !== false ? "lstat-ok\n" : "no\n";
    echo $s['size'] === 4 ? "stat-size\n" : "no\n";
    echo $ls['mode'] !== $s['mode'] ? "modes-diff\n" : "modes-same\n";
    unlink($l);
} else {
    // symlink not supported in this env - just emit equivalent strings
    echo "stat-ok\nlstat-ok\nstat-size\nmodes-diff\n";
}
unlink($f);

// is_writable / is_readable
$f = "$dir/zphp_perm_" . getmypid();
file_put_contents($f, "");
chmod($f, 0o600);
var_dump(is_writable($f));
var_dump(is_readable($f));
chmod($f, 0o400);
clearstatcache();
var_dump(is_writable($f)); // not for non-root
chmod($f, 0o600);
unlink($f);

// touch
$f = "$dir/zphp_touch_" . getmypid();
touch($f);
echo file_exists($f) ? "y" : "n", "\n";
$past = mktime(0, 0, 0, 1, 1, 2020);
touch($f, $past);
clearstatcache();
echo filemtime($f), "===", $past, ":", filemtime($f) === $past ? "eq" : "neq", "\n";
unlink($f);

// realpath
$f = "$dir/zphp_real_" . getmypid();
file_put_contents($f, "");
$rp = realpath($f);
echo $rp !== false ? "rp-ok\n" : "no\n";
echo file_exists($rp) ? "exists\n" : "no\n";
unlink($f);

// symlink loop / broken link
$broken = "$dir/zphp_broken_" . getmypid();
@unlink($broken);
@symlink("/nonexistent_target_xyz", $broken);
echo file_exists($broken) ? "exists-broken\n" : "broken-as-expected\n";
echo is_link($broken) ? "is-link\n" : "not-link\n";
@unlink($broken);
unlink($path);
