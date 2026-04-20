<?php
// pre-built phar embedded as base64. contains:
//   readme.md, lib/util.php, data/config.json, a/b/c/deep.txt
$pharB64 = 'PD9waHAKZWNobyAic3R1YiIuUEhQX0VPTDsKX19IQUxUX0NPTVBJTEVSKCk7ID8+DQq+AAAABAAAABEAAAABAAkAAAB0ZXN0LnBoYXIAAAAACQAAAHJlYWRtZS5tZAsAAABGNOZpCwAAAFIUCsSkAQAAAAAAAAwAAABsaWIvdXRpbC5waHAiAAAARjTmaSIAAACv9V+LpAEAAAAAAAAQAAAAZGF0YS9jb25maWcuanNvbg8AAABGNOZpDwAAANLfIEqkAQAAAAAAAA4AAABhL2IvYy9kZWVwLnR4dAUAAABGNOZpBQAAAIK4niekAQAAAAAAAEhlbGxvIHBoYXIKPD9waHAKZnVuY3Rpb24gZigpIHsgcmV0dXJuIDQyOyB9CnsibmFtZSI6InRlc3QifWRlZXAKn/k37nhii0YNsBJgRAAI+Z9UXDqSbCjBI8PUu+5Ro+4DAAAAR0JNQg==';

$pharFile = sys_get_temp_dir() . '/zphp_phar_compat_' . mt_rand(1000000, 9999999) . '.phar';
file_put_contents($pharFile, base64_decode($pharB64));

echo file_get_contents("phar://$pharFile/readme.md");
echo file_get_contents("phar://$pharFile/lib/util.php");
echo file_get_contents("phar://$pharFile/data/config.json") . "\n";
echo file_get_contents("phar://$pharFile/a/b/c/deep.txt");

echo "exists readme: " . (file_exists("phar://$pharFile/readme.md") ? "y" : "n") . "\n";
echo "exists deep: " . (file_exists("phar://$pharFile/a/b/c/deep.txt") ? "y" : "n") . "\n";
echo "exists missing: " . (file_exists("phar://$pharFile/nope") ? "y" : "n") . "\n";
echo "is_file readme: " . (is_file("phar://$pharFile/readme.md") ? "y" : "n") . "\n";
echo "is_file lib: " . (is_file("phar://$pharFile/lib") ? "y" : "n") . "\n";
echo "is_dir lib: " . (is_dir("phar://$pharFile/lib") ? "y" : "n") . "\n";
echo "is_dir a/b: " . (is_dir("phar://$pharFile/a/b") ? "y" : "n") . "\n";
echo "is_dir missing: " . (is_dir("phar://$pharFile/zzz") ? "y" : "n") . "\n";

$f = fopen("phar://$pharFile/readme.md", 'r');
echo "fread1: " . fread($f, 5) . "\n";
echo "fread2: " . fread($f, 100);
echo "feof: " . (feof($f) ? "y" : "n") . "\n";
rewind($f);
echo "rewind: " . fread($f, 100);
fclose($f);

$r = @file_get_contents("phar://$pharFile/missing");
echo "missing read: " . var_export($r, true) . "\n";

echo "phar in wrappers: " . (in_array('phar', stream_get_wrappers()) ? "y" : "n") . "\n";

@unlink($pharFile);
