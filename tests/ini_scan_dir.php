<?php
// PHP_INI_SCAN_DIR: the *.ini files of each listed directory load after
// php.ini, in name order, and -d still wins over them
$base = sys_get_temp_dir() . '/zphp-ini-scan-' . getmypid();
@mkdir($base);
@mkdir("$base/a");
@mkdir("$base/b");
@mkdir("$base/a/sub.ini");
file_put_contents("$base/a/20-tz.ini", "date.timezone = Antarctica/McMurdo\n");
file_put_contents("$base/a/10-tz.ini", "date.timezone = Europe/Oslo\nprecision = 7\n");
file_put_contents("$base/a/notes.txt", "date.timezone = Asia/Tokyo\n");
file_put_contents("$base/a/x.ini.bak", "precision = 3\n");
file_put_contents("$base/b/30.ini", "serialize_precision = 5\n");

$php = escapeshellarg(PHP_BINARY);
$probe = escapeshellarg('$f = php_ini_scanned_files(); var_dump($f === false ? false : str_replace(' . var_export($base, true) . ', "BASE", $f)); var_dump(ini_get("date.timezone"), ini_get("precision"), ini_get("serialize_precision"));');
$run = function (string $env, string $flags = '') use ($php, $probe) {
    echo "-- ", str_replace($GLOBALS["base"], "BASE", $env), " $flags\n";
    putenv($env);
    passthru("$php $flags -r $probe");
};
$run('PHP_INI_SCAN_DIR=');
$run("PHP_INI_SCAN_DIR=$base/a");
$run("PHP_INI_SCAN_DIR=$base/a/");
$run("PHP_INI_SCAN_DIR=$base/b:$base/a");
$run("PHP_INI_SCAN_DIR=$base/missing");
$run("PHP_INI_SCAN_DIR=$base/missing:$base/b");
$run("PHP_INI_SCAN_DIR=$base/a", '-d precision=9');
$run("PHP_INI_SCAN_DIR=$base/a", '-n');

foreach (['a/20-tz.ini', 'a/10-tz.ini', 'a/notes.txt', 'a/x.ini.bak', 'b/30.ini'] as $f) unlink("$base/$f");
rmdir("$base/a/sub.ini");
rmdir("$base/a");
rmdir("$base/b");
rmdir($base);
