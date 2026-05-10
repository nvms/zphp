<?php
$dir = sys_get_temp_dir() . "/_zphp_streams_probe";
if (is_dir($dir)) {
    foreach (glob("$dir/*") as $f) @unlink($f);
    rmdir($dir);
}
mkdir($dir);

$f1 = "$dir/file1.txt";
$f2 = "$dir/file2.txt";

file_put_contents($f1, "hello world");
echo file_get_contents($f1), "\n";
echo file_exists($f1) ? "y" : "n", "\n";
echo file_exists("$dir/nope") ? "y" : "n", "\n";
echo filesize($f1), "\n";

file_put_contents($f2, "line1\nline2\nline3\n");
echo file_get_contents($f2), "\n";
echo filesize($f2), "\n";

$h = fopen($f1, "r");
echo fread($h, 5), "\n";
echo ftell($h), "\n";
fseek($h, 0);
echo ftell($h), "\n";
echo fread($h, 1024), "\n";
echo feof($h) ? "y" : "n", "\n";
fclose($h);

$h = fopen($f1, "rb");
echo fread($h, 5), "\n";
fclose($h);

$h = fopen("$dir/new.txt", "w");
fwrite($h, "fresh content");
fclose($h);
echo file_get_contents("$dir/new.txt"), "\n";

$h = fopen("$dir/new.txt", "a");
fwrite($h, " - appended");
fclose($h);
echo file_get_contents("$dir/new.txt"), "\n";

$h = fopen("$dir/new.txt", "w");
fwrite($h, "overwritten");
fclose($h);
echo file_get_contents("$dir/new.txt"), "\n";

$h = fopen("$dir/new.txt", "r+");
fseek($h, 5);
fwrite($h, "WROTE");
fclose($h);
echo file_get_contents("$dir/new.txt"), "\n";

$h = fopen("$dir/new.txt", "r");
fseek($h, 0, SEEK_END);
echo ftell($h), "\n";
fseek($h, -5, SEEK_END);
echo fread($h, 1024), "\n";
fseek($h, 2, SEEK_SET);
echo fread($h, 3), "\n";
fseek($h, 0);
fseek($h, 4, SEEK_CUR);
echo fread($h, 3), "\n";
fclose($h);

copy($f1, "$dir/copy.txt");
echo file_get_contents("$dir/copy.txt"), "\n";
echo file_exists("$dir/copy.txt") ? "y" : "n", "\n";

rename("$dir/copy.txt", "$dir/renamed.txt");
echo file_exists("$dir/copy.txt") ? "y" : "n", "\n";
echo file_exists("$dir/renamed.txt") ? "y" : "n", "\n";

unlink("$dir/renamed.txt");
echo file_exists("$dir/renamed.txt") ? "y" : "n", "\n";

$h = fopen("$dir/multi.txt", "w");
fwrite($h, "line1\n");
fwrite($h, "line2\n");
fwrite($h, "line3\n");
fclose($h);
$lines = file("$dir/multi.txt");
print_r($lines);

$lines = file("$dir/multi.txt", FILE_IGNORE_NEW_LINES);
print_r($lines);

$h = fopen("$dir/multi.txt", "r");
while (($line = fgets($h)) !== false) echo "[", rtrim($line), "]";
fclose($h);
echo "\n";

$h = fopen("$dir/multi.txt", "r");
echo fgetc($h), fgetc($h), fgetc($h), "\n";
fclose($h);

$h = fopen("$dir/multi.txt", "r");
echo fread($h, 6), "\n";
echo ftell($h), "\n";
fclose($h);

mkdir("$dir/sub");
file_put_contents("$dir/sub/a.txt", "A");
file_put_contents("$dir/sub/b.txt", "B");
file_put_contents("$dir/sub/c.txt", "C");

$entries = scandir("$dir/sub");
$entries = array_values(array_filter($entries, fn($x) => $x !== "." && $x !== ".."));
sort($entries);
print_r($entries);

$entries = scandir("$dir/sub", SCANDIR_SORT_DESCENDING);
$entries = array_values(array_filter($entries, fn($x) => $x !== "." && $x !== ".."));
print_r($entries);

$h = fopen($f1, "r");
echo fseek($h, 100), "\n";
echo ftell($h), "\n";
echo fread($h, 1) === "" ? "y" : "n", "\n";
echo feof($h) ? "y" : "n", "\n";
fclose($h);

echo @file_get_contents("$dir/nope") === false ? "y" : "n", "\n";

$h = @fopen("$dir/non_existent_directory/file.txt", "r");
echo $h === false ? "y" : "n", "\n";

echo is_file($f1) ? "y" : "n", "\n";
echo is_dir($dir) ? "y" : "n", "\n";
echo is_dir($f1) ? "y" : "n", "\n";
echo is_file($dir) ? "y" : "n", "\n";

file_put_contents("$dir/binary.bin", "\x00\x01\x02\x03\x04");
echo strlen(file_get_contents("$dir/binary.bin")), "\n";
echo bin2hex(file_get_contents("$dir/binary.bin")), "\n";

file_put_contents("$dir/append.txt", "first ", FILE_APPEND);
file_put_contents("$dir/append.txt", "second ", FILE_APPEND);
file_put_contents("$dir/append.txt", "third", FILE_APPEND);
echo file_get_contents("$dir/append.txt"), "\n";

foreach (glob("$dir/*") as $f) {
    if (is_dir($f)) {
        foreach (glob("$f/*") as $sf) @unlink($sf);
        rmdir($f);
    } else {
        @unlink($f);
    }
}
rmdir($dir);
echo file_exists($dir) ? "y" : "n", "\n";
echo "done\n";
