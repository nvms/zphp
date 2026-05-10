<?php
$dir = sys_get_temp_dir();
$path = "$dir/zphp_io3_" . getmypid();

// file_put_contents FILE_APPEND
file_put_contents($path, "first\n");
file_put_contents($path, "second\n", FILE_APPEND);
file_put_contents($path, "third\n", FILE_APPEND);
echo file_get_contents($path);

// LOCK_EX
file_put_contents($path, "locked\n", FILE_APPEND | LOCK_EX);
echo file_get_contents($path);

// file_get_contents with offset/length
file_put_contents($path, "0123456789ABCDEF");
echo file_get_contents($path, false, null, 3, 5), "\n"; // 34567
echo file_get_contents($path, false, null, -3), "\n"; // DEF

// fread limits
$f = fopen($path, "r");
try { echo fread($f, 0), "|\n"; } catch (\ValueError $e) { echo "ve-zero\n"; }
echo fread($f, 5), "|\n"; // 01234
echo fread($f, 100), "|\n"; // rest
fclose($f);

// fgets with length
file_put_contents($path, "hello\nworld\nfoo bar\n");
$f = fopen($path, "r");
echo fgets($f), "|"; // "hello\n"
echo fgets($f, 3), "|"; // "wo" (length 3 = read 2 chars + null)
echo fgets($f), "|"; // rest of "world\n"
echo fgets($f), "|"; // "foo bar\n"
echo var_export(fgets($f), true), "\n"; // false (EOF)
fclose($f);

// fgetc EOF
$f = fopen($path, "r");
fseek($f, 0, SEEK_END);
var_dump(fgetc($f)); // false
fclose($f);

// file() with various flags
file_put_contents($path, "line1\n\nline3\nline4\n\n");
$lines = file($path);
print_r($lines); // each with \n

$lines = file($path, FILE_IGNORE_NEW_LINES);
print_r($lines); // no \n

$lines = file($path, FILE_SKIP_EMPTY_LINES);
print_r($lines); // no empty lines

$lines = file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
print_r($lines);

// readfile
ob_start();
readfile($path);
$out = ob_get_clean();
echo "[$out]\n";

// fopen modes
$f = fopen($path, "w"); // truncates
fwrite($f, "new");
fclose($f);
echo file_get_contents($path), "|\n";

$f = fopen($path, "a"); // appends
fwrite($f, "MORE");
fclose($f);
echo file_get_contents($path), "|\n";

$f = fopen($path, "r+"); // read/write, no truncate
fwrite($f, "X");
fclose($f);
echo file_get_contents($path), "|\n";

$f = fopen($path, "w+"); // truncate, read/write
echo ftell($f), "\n"; // 0
fwrite($f, "abc");
echo ftell($f), "\n"; // 3
fseek($f, 0);
echo fread($f, 100), "|\n"; // abc
fclose($f);

// fopen "x" exclusive create - fails if file exists
try {
    $f = @fopen($path, "x");
    echo $f === false ? "exists-fail\n" : "ok\n";
} catch (\Throwable $e) { echo "err\n"; }

unlink($path);
$f = fopen($path, "x");
echo is_resource($f) || is_object($f) ? "created\n" : "no\n";
fclose($f);

// fwrite with limit
$f = fopen($path, "w");
fwrite($f, "hello world", 5);
fclose($f);
echo file_get_contents($path), "\n"; // "hello"

// rewind / fread cycle
$f = fopen($path, "r+");
fread($f, 100);
echo ftell($f), "\n";
rewind($f);
echo ftell($f), "\n";
fwrite($f, "X");
fclose($f);
echo file_get_contents($path), "|\n";

unlink($path);

// non-existent file
var_dump(@file_get_contents("/nonexistent_file_xyz_zphp"));
echo file_exists("/nonexistent_file_xyz_zphp") ? "y" : "n", "\n";
