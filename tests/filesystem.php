<?php

$tmpdir = sys_get_temp_dir() . "/zphp_fs_test_" . uniqid();
mkdir($tmpdir);
echo is_dir($tmpdir) ? "mkdir ok\n" : "mkdir FAIL\n";

// fopen/fwrite/fclose
$f = fopen("$tmpdir/test.txt", "w");
fwrite($f, "hello world\n");
fwrite($f, "second line\n");
fclose($f);
echo file_exists("$tmpdir/test.txt") ? "fwrite ok\n" : "fwrite FAIL\n";

// fopen/fread
$f = fopen("$tmpdir/test.txt", "r");
$data = fread($f, 5);
echo "fread: $data\n";  // fread: hello
fclose($f);

// fgets
$f = fopen("$tmpdir/test.txt", "r");
$line = fgets($f);
echo "fgets: " . trim($line) . "\n";  // fgets: hello world
$line2 = fgets($f);
echo "fgets2: " . trim($line2) . "\n";  // fgets2: second line
fclose($f);

// feof
$f = fopen("$tmpdir/test.txt", "r");
$lines = 0;
while (!feof($f)) {
    $l = fgets($f);
    if ($l !== false) $lines++;
}
fclose($f);
echo "lines: $lines\n";  // lines: 2

// fseek/ftell
$f = fopen("$tmpdir/test.txt", "r");
fseek($f, 6);
echo "ftell: " . ftell($f) . "\n";  // ftell: 6
$word = fread($f, 5);
echo "seeked: $word\n";  // seeked: world
fclose($f);

// file() - read into array
$lines = file("$tmpdir/test.txt");
echo "file count: " . count($lines) . "\n";  // file count: 2

// filesize
echo "size: " . filesize("$tmpdir/test.txt") . "\n";  // size: 24

// copy
copy("$tmpdir/test.txt", "$tmpdir/copy.txt");
echo file_exists("$tmpdir/copy.txt") ? "copy ok\n" : "copy FAIL\n";

// rename
rename("$tmpdir/copy.txt", "$tmpdir/renamed.txt");
echo file_exists("$tmpdir/renamed.txt") ? "rename ok\n" : "rename FAIL\n";
echo !file_exists("$tmpdir/copy.txt") ? "old gone\n" : "old still there\n";

// scandir
$entries = scandir($tmpdir);
echo "scandir: " . count($entries) . "\n";  // scandir: 4 (. .. test.txt renamed.txt)

// is_readable/is_writable
echo is_readable("$tmpdir/test.txt") ? "readable\n" : "not readable\n";
echo is_writable("$tmpdir/test.txt") ? "writable\n" : "not writable\n";

// filetype
echo "type: " . filetype("$tmpdir/test.txt") . "\n";  // type: file
echo "dirtype: " . filetype($tmpdir) . "\n";  // dirtype: dir

// unlink
unlink("$tmpdir/test.txt");
unlink("$tmpdir/renamed.txt");
echo !file_exists("$tmpdir/test.txt") ? "unlink ok\n" : "unlink FAIL\n";

// rmdir
rmdir($tmpdir);
echo !is_dir($tmpdir) ? "rmdir ok\n" : "rmdir FAIL\n";

// append mode
$tmpfile = tempnam("/tmp", "zphp_append_");
$f = fopen($tmpfile, "w");
fwrite($f, "first\n");
fclose($f);
$f = fopen($tmpfile, "a");
fwrite($f, "second\n");
fclose($f);
$content = file_get_contents($tmpfile);
echo "append: " . trim($content) . "\n";
unlink($tmpfile);

echo "done\n";
