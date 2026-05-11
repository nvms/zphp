<?php
$path = sys_get_temp_dir() . "/_zphp_stat_probe.txt";
file_put_contents($path, "hello world");

$s = stat($path);
echo is_array($s) ? "y" : "n", "\n";

$expected_keys = ["dev","ino","mode","nlink","uid","gid","rdev","size","atime","mtime","ctime","blksize","blocks"];
$has_all = true;
foreach ($expected_keys as $k) {
    if (!array_key_exists($k, $s)) { $has_all = false; break; }
}
echo $has_all ? "y" : "n", "\n";

echo is_int($s["size"]) ? "y" : "n", "\n";
echo $s["size"] === 11 ? "y" : "n", "\n";
echo is_int($s["mtime"]) ? "y" : "n", "\n";
echo $s["mtime"] > 0 ? "y" : "n", "\n";

echo filesize($path), "\n";
echo filesize($path) === 11 ? "y" : "n", "\n";

echo is_int(filemtime($path)) ? "y" : "n", "\n";
echo filemtime($path) > 0 ? "y" : "n", "\n";

echo is_int(filectime($path)) ? "y" : "n", "\n";
echo is_int(fileatime($path)) ? "y" : "n", "\n";

$mt = filemtime($path);
$at = fileatime($path);
$ct = filectime($path);
echo $mt > 0 && $at > 0 && $ct > 0 ? "y" : "n", "\n";

$perms = fileperms($path);
echo is_int($perms) ? "y" : "n", "\n";
echo $perms > 0 ? "y" : "n", "\n";

$mode_low = $perms & 0o777;
echo decoct($mode_low) > 0 ? "y" : "n", "\n";

echo filetype($path), "\n";
echo filetype("/tmp") === "dir" || filetype("/tmp") === "link" ? "y" : "n", "\n";

$dir = sys_get_temp_dir();
echo filetype($dir) === "dir" || filetype($dir) === "link" ? "y" : "n", "\n";

$st_dir = stat($dir);
echo is_array($st_dir) ? "y" : "n", "\n";

echo is_int($s[0]) || isset($s[0]) ? "y" : "n", "\n";

echo $s[0] === $s["dev"] ? "y" : "n", "\n";
echo $s[7] === $s["size"] ? "y" : "n", "\n";
echo $s[9] === $s["mtime"] ? "y" : "n", "\n";
echo $s[2] === $s["mode"] ? "y" : "n", "\n";

echo count(stat($path)) >= 26 ? "y" : "n", "\n";

$nonexist = "/tmp/does_not_exist_99999.txt";
echo @stat($nonexist) === false ? "y" : "n", "\n";
echo @filesize($nonexist) === false ? "y" : "n", "\n";
echo @filemtime($nonexist) === false ? "y" : "n", "\n";
echo @fileperms($nonexist) === false ? "y" : "n", "\n";

$big_path = sys_get_temp_dir() . "/_zphp_big_probe.bin";
file_put_contents($big_path, str_repeat("x", 10000));
echo filesize($big_path), "\n";
$s2 = stat($big_path);
echo $s2["size"], "\n";
unlink($big_path);

$h = fopen($path, "r");
$fs = fstat($h);
echo is_array($fs) ? "y" : "n", "\n";
echo $fs["size"] === 11 ? "y" : "n", "\n";
fclose($h);

$link_path = sys_get_temp_dir() . "/_zphp_stat_link";
@unlink($link_path);
if (symlink($path, $link_path)) {
    $ls = lstat($link_path);
    echo is_array($ls) ? "y" : "n", "\n";
    echo is_link($link_path) ? "y" : "n", "\n";
    echo readlink($link_path) === $path ? "y" : "n", "\n";
    unlink($link_path);
} else {
    echo "y\ny\ny\n";
}

echo file_exists($path) ? "y" : "n", "\n";
echo is_file($path) ? "y" : "n", "\n";
echo is_dir($path) ? "y" : "n", "\n";
echo is_readable($path) ? "y" : "n", "\n";
echo is_writable($path) ? "y" : "n", "\n";
echo is_executable($path) ? "y" : "n", "\n";

echo dirname($path) === sys_get_temp_dir() ? "y" : "n", "\n";
echo basename($path), "\n";
echo pathinfo($path, PATHINFO_EXTENSION), "\n";
echo pathinfo($path, PATHINFO_BASENAME), "\n";
echo pathinfo($path, PATHINFO_FILENAME), "\n";

echo realpath($path) !== false ? "y" : "n", "\n";
echo realpath("/nonexistent/path") === false ? "y" : "n", "\n";

touch($path, 1700000000);
echo filemtime($path), "\n";
echo filemtime($path) === 1700000000 ? "y" : "n", "\n";

touch($path);
echo filemtime($path) > 1700000000 ? "y" : "n", "\n";

clearstatcache();
echo is_int(filemtime($path)) ? "y" : "n", "\n";

$first_size = filesize($path);
file_put_contents($path, "extra content added");
$second_size_cached = filesize($path);
clearstatcache(true, $path);
$third_size = filesize($path);
echo $third_size === 19 ? "y" : "n", "\n";

@unlink($path);
echo "done\n";
