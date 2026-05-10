<?php
$dir = sys_get_temp_dir();
$path = "$dir/zphp_fio_static";

// file_put_contents creates
$n = file_put_contents($path, "hello");
echo $n, "\n"; // 5
echo file_get_contents($path), "\n";

// overwrite
$n = file_put_contents($path, "world");
echo $n, "\n";
echo file_get_contents($path), "\n";

// append
file_put_contents($path, "!!", FILE_APPEND);
echo file_get_contents($path), "\n";

// lock_ex flag
file_put_contents($path, "data", LOCK_EX);
echo file_get_contents($path), "\n";

// append + lock
file_put_contents($path, "+more", FILE_APPEND | LOCK_EX);
echo file_get_contents($path), "\n";

// file_get_contents with offset/length
file_put_contents($path, "0123456789");
echo file_get_contents($path, false, null, 3), "\n";       // 3456789
echo file_get_contents($path, false, null, 3, 4), "\n";    // 3456
echo file_get_contents($path, false, null, 0, 3), "\n";    // 012

// non-existent file warning (architectural - PHP emits Warning on missing file)
$r = @file_get_contents("/nonexistent/path/zphp_xx");
echo $r === false ? "false\n" : "got\n";

// fopen modes - r
$f = fopen($path, "r");
echo fread($f, 5), "\n"; // 01234
echo ftell($f), "\n";    // 5
fclose($f);

// w truncates
$f = fopen($path, "w");
fwrite($f, "abc");
fclose($f);
echo file_get_contents($path), "\n"; // abc

// a appends, fopen positions at end
file_put_contents($path, "ABC");
$f = fopen($path, "a");
echo ftell($f), "\n"; // 3
fwrite($f, "DEF");
fclose($f);
echo file_get_contents($path), "\n"; // ABCDEF

// r+ read+write
file_put_contents($path, "hello");
$f = fopen($path, "r+");
echo fread($f, 2), "\n"; // he
fwrite($f, "XX");
fclose($f);
echo file_get_contents($path), "\n"; // heXXo

// w+ truncates+read+write
$f = fopen($path, "w+");
fwrite($f, "fresh");
rewind($f);
echo fread($f, 100), "\n"; // fresh
fclose($f);

// a+ - append + read
file_put_contents($path, "AB");
$f = fopen($path, "a+");
echo ftell($f), "\n"; // 2 (PHP positions at end for write)
rewind($f);
echo fread($f, 100), "\n"; // AB
fwrite($f, "CD");
fclose($f);
echo file_get_contents($path), "\n"; // ABCD

// fseek + ftell
file_put_contents($path, "0123456789");
$f = fopen($path, "r");
fseek($f, 3);
echo ftell($f), "\n"; // 3
echo fread($f, 2), "\n"; // 34
fseek($f, -2, SEEK_END);
echo ftell($f), "\n"; // 8
echo fread($f, 2), "\n"; // 89
fseek($f, 2, SEEK_CUR);
// after fread: pos 10 + 2 = 12 ... actually after reading 89, pos is 10. cur+2 = 12.
// can seek beyond end; ftell = 12
echo ftell($f), "\n"; // 12
fclose($f);

// rewind
$f = fopen($path, "r");
fread($f, 5);
rewind($f);
echo ftell($f), "\n"; // 0
fclose($f);

// fread up to length
file_put_contents($path, "hello world");
$f = fopen($path, "r");
echo fread($f, 5), "|\n"; // hello
echo fread($f, 100), "|\n"; // " world" (the rest)
echo fread($f, 100), "|\n"; // "" at EOF
var_dump(feof($f));
fclose($f);

// fwrite returns bytes
$f = fopen($path, "w");
$n = fwrite($f, "abcde");
echo $n, "\n";
fclose($f);

// fwrite with length param
$f = fopen($path, "w");
$n = fwrite($f, "abcdefg", 3);
fclose($f);
echo $n, "\n"; // 3
echo file_get_contents($path), "\n"; // abc

// fgets line-by-line
file_put_contents($path, "line1\nline2\nline3\n");
$f = fopen($path, "r");
while (($line = fgets($f)) !== false) {
    echo "[", trim($line), "]";
}
echo "\n";
fclose($f);

// file() default
print_r(file($path));

// FILE_IGNORE_NEW_LINES
print_r(file($path, FILE_IGNORE_NEW_LINES));

// FILE_SKIP_EMPTY_LINES
file_put_contents($path, "line1\n\nline2\n\nline3");
print_r(file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES));

// fputs alias for fwrite
$f = fopen($path, "w");
fputs($f, "fputs-test");
fclose($f);
echo file_get_contents($path), "\n";

// fileinfo: file_exists, is_file, is_dir
file_put_contents($path, "exists");
var_dump(file_exists($path));
var_dump(is_file($path));
var_dump(is_dir($path));
var_dump(is_readable($path));
var_dump(is_writable($path));

// filesize
echo filesize($path), "\n";

// unlink
unlink($path);
var_dump(file_exists($path));

// tmpfile (simple smoke - PHP returns resource, zphp probably FileHandle)
$f = tmpfile();
fwrite($f, "tmp");
rewind($f);
echo fread($f, 100), "\n";
fclose($f);

// fgetc
file_put_contents($path, "abc");
$f = fopen($path, "r");
echo fgetc($f), fgetc($f), fgetc($f), "\n"; // abc
$c = fgetc($f);
var_dump($c); // false at EOF
fclose($f);
unlink($path);

// touch creates
$path2 = "$dir/zphp_touch_static";
@unlink($path2);
var_dump(file_exists($path2));
touch($path2);
var_dump(file_exists($path2));
echo filesize($path2), "\n"; // 0
unlink($path2);

// copy
file_put_contents($path, "src");
copy($path, $path . ".copy");
echo file_get_contents($path . ".copy"), "\n";
unlink($path);
unlink($path . ".copy");

// rename
file_put_contents($path, "rename");
rename($path, $path . ".new");
var_dump(file_exists($path));
echo file_get_contents($path . ".new"), "\n";
unlink($path . ".new");
