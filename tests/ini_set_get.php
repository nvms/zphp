<?php
// ini_set on a known directive (date.timezone)
$old = ini_set('date.timezone', 'UTC');
echo "old:$old\n";
echo ini_get('date.timezone'), "\n";
ini_set('date.timezone', 'Europe/Paris');
echo ini_get('date.timezone'), "\n";
ini_set('date.timezone', $old);

// ini_set on unknown directive returns false
var_dump(ini_set('nonexistent_xyz', 'value'));

// ini_get for unset returns false
var_dump(ini_get('nonexistent_xyz'));

// php_sapi_name
echo php_sapi_name(), "\n";
echo PHP_SAPI, "\n";

// php_uname components
var_dump(strlen(php_uname('s')) > 0);
var_dump(strlen(php_uname('n')) > 0);
var_dump(strlen(php_uname('m')) > 0);

// ftruncate shrink
$fh = fopen('php://memory', 'w+');
fwrite($fh, "Hello World!");
ftruncate($fh, 5);
rewind($fh);
echo stream_get_contents($fh), "|\n";
fclose($fh);

// ftruncate grow (zero-fill)
$fh = fopen('php://memory', 'w+');
fwrite($fh, "abc");
ftruncate($fh, 10);
rewind($fh);
echo bin2hex(stream_get_contents($fh)), "\n";
fclose($fh);

// dirname levels
echo dirname('/a/b/c/d.txt'), "\n";
echo dirname('/a/b/c/d.txt', 2), "\n";
echo dirname('/a/b/c/d.txt', 3), "\n";
echo dirname('/a/b/c/d.txt', 4), "\n";
echo dirname('/a/b/c/d.txt', 100), "\n";
echo dirname('relative/path'), "\n";
echo dirname('flat'), "\n";
