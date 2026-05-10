<?php
$path = sys_get_temp_dir() . "/zphp_perm_test";
file_put_contents($path, "0123456789");

$f = fopen($path, "r+");
echo filesize($path), "\n";

ftruncate($f, 5);
fclose($f);
clearstatcache();
echo filesize($path), "\n";
echo file_get_contents($path), "\n";

$f = fopen($path, "r+");
ftruncate($f, 10);
fclose($f);
clearstatcache();
echo filesize($path), "\n";

ftruncate(fopen($path, "r+"), 0);
clearstatcache();
echo filesize($path), "\n";

file_put_contents($path, "data");
$f = fopen($path, "r");
$ok = flock($f, LOCK_SH);
var_dump($ok);
flock($f, LOCK_UN);
fclose($f);

$f = fopen($path, "r+");
$ok = flock($f, LOCK_EX);
var_dump($ok);
flock($f, LOCK_UN);
fclose($f);

$f = fopen($path, "r+");
$ok = flock($f, LOCK_EX | LOCK_NB);
var_dump($ok);
flock($f, LOCK_UN);
fclose($f);

chmod($path, 0644);
echo decoct(fileperms($path) & 0777), "\n";

chmod($path, 0755);
echo decoct(fileperms($path) & 0777), "\n";

chmod($path, 0600);
echo decoct(fileperms($path) & 0777), "\n";

$old = umask(0022);
echo decoct($old & 0777), "\n";
$cur = umask();
echo decoct($cur & 0777), "\n";
umask($old);

$file2 = sys_get_temp_dir() . "/zphp_umask_test";
@unlink($file2);
$old = umask(0077);
file_put_contents($file2, "x");
clearstatcache();
echo decoct(fileperms($file2) & 0777), "\n"; // 0600
umask($old);
unlink($file2);

echo basename("foo.txt"), "\n";
echo basename("./foo.txt"), "\n";
echo basename("./foo.txt", ".txt"), "\n";
echo basename("../foo.txt"), "\n";
echo basename("/abs/path/foo.txt"), "\n";

$p = realpath("/tmp");
echo $p === false ? "false" : (strlen($p) > 0 ? "ok" : "empty"), "\n";

$p = realpath("/tmp/.");
echo $p === false ? "false" : (strlen($p) > 0 ? "ok" : "empty"), "\n";

var_dump(realpath("/nonexistent/zphp_xx_$$"));

$file = sys_get_temp_dir() . "/zphp_rp_test";
file_put_contents($file, "x");
$rp = realpath($file);
echo strlen($rp) > 0 ? "real-ok" : "real-bad", "\n";
unlink($file);

var_dump(is_readable($path));
var_dump(is_writable($path));
echo is_executable("/bin/sh") ? "y" : "n", "\n";

echo fileowner($path) > 0 ? "owner-ok" : "owner-bad", "\n";
echo filegroup($path) >= 0 ? "group-ok" : "group-bad", "\n";

$st = stat($path);
echo $st["size"] === filesize($path) ? "stat-size-ok" : "stat-size-bad", "\n";
echo isset($st["mtime"]) ? "mtime" : "no", "\n";

$st = lstat($path);
echo isset($st["size"]) ? "lstat-ok" : "no", "\n";

echo fileatime($path) > 0 ? "atime-ok" : "atime-bad", "\n";
echo filemtime($path) > 0 ? "mtime-ok" : "mtime-bad", "\n";
echo filectime($path) > 0 ? "ctime-ok" : "ctime-bad", "\n";

echo realpath(".") !== false ? "rp-dot" : "no-rp-dot", "\n";

unlink($path);
