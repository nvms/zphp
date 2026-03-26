<?php
// covers: file_get_contents, file_put_contents, file_exists, is_file, is_dir,
//   basename, dirname, pathinfo, mkdir, rmdir, unlink, copy, rename, glob,
//   scandir, file, fopen, fclose, fwrite, fread, fgets, feof, fseek, ftell,
//   rewind, ftruncate, filesize, tempnam, sys_get_temp_dir

$tmp = sys_get_temp_dir() . '/zphp_file_io_test_' . time();

// --- directory operations ---

echo "=== Directory Ops ===\n";

echo "exists before: " . (file_exists($tmp) ? 'yes' : 'no') . "\n";
mkdir($tmp, 0755, true);
echo "exists after: " . (file_exists($tmp) ? 'yes' : 'no') . "\n";
echo "is_dir: " . (is_dir($tmp) ? 'yes' : 'no') . "\n";
echo "is_file: " . (is_file($tmp) ? 'yes' : 'no') . "\n";

// --- file write/read ---

echo "\n=== File Write/Read ===\n";

$file = "$tmp/test.txt";
file_put_contents($file, "Hello, World!\nSecond line.\nThird line.");
echo "written: " . (file_exists($file) ? 'yes' : 'no') . "\n";
echo "is_file: " . (is_file($file) ? 'yes' : 'no') . "\n";
echo "size: " . filesize($file) . "\n";

$content = file_get_contents($file);
echo "read: $content\n";

// --- file() function ---

echo "\n=== File Lines ===\n";

$lines = file($file);
echo "line count: " . count($lines) . "\n";
foreach ($lines as $i => $line) {
    echo "  [$i]: " . rtrim($line) . "\n";
}

// --- path functions ---

echo "\n=== Path Functions ===\n";

echo "basename: " . basename($file) . "\n";
echo "basename ext: " . basename($file, '.txt') . "\n";
echo "dirname: " . basename(dirname($file)) . "\n";

$info = pathinfo($file);
echo "extension: " . $info['extension'] . "\n";
echo "filename: " . $info['filename'] . "\n";

// --- append mode ---

echo "\n=== Append ===\n";

file_put_contents($file, "\nFourth line.", FILE_APPEND);
$lines_after = file($file);
echo "lines after append: " . count($lines_after) . "\n";
echo "last line: " . rtrim(end($lines_after)) . "\n";

// --- copy and rename ---

echo "\n=== Copy/Rename ===\n";

$copy_file = "$tmp/copy.txt";
copy($file, $copy_file);
echo "copy exists: " . (file_exists($copy_file) ? 'yes' : 'no') . "\n";
echo "copy matches: " . (file_get_contents($copy_file) === file_get_contents($file) ? 'yes' : 'no') . "\n";

$renamed = "$tmp/renamed.txt";
rename($copy_file, $renamed);
echo "copy gone: " . (file_exists($copy_file) ? 'yes' : 'no') . "\n";
echo "renamed exists: " . (file_exists($renamed) ? 'yes' : 'no') . "\n";

// --- fopen/fwrite/fread ---

echo "\n=== Stream IO ===\n";

$fp = fopen("$tmp/stream.txt", 'w');
fwrite($fp, "Line 1\n");
fwrite($fp, "Line 2\n");
fwrite($fp, "Line 3\n");
fclose($fp);

$fp = fopen("$tmp/stream.txt", 'r');
$first = fgets($fp);
echo "first line: " . rtrim($first) . "\n";
echo "tell after first: " . ftell($fp) . "\n";

$second = fgets($fp);
echo "second line: " . rtrim($second) . "\n";

rewind($fp);
echo "tell after rewind: " . ftell($fp) . "\n";
$again = fgets($fp);
echo "first again: " . rtrim($again) . "\n";

fseek($fp, 0, SEEK_END);
$end_pos = ftell($fp);
echo "end position: $end_pos\n";
fclose($fp);

// --- ftruncate ---

echo "\n=== Truncate ===\n";

$fp = fopen("$tmp/trunc.txt", 'w');
fwrite($fp, "Hello World");
ftruncate($fp, 5);
fclose($fp);
echo "truncated: " . file_get_contents("$tmp/trunc.txt") . "\n";
echo "truncated size: " . filesize("$tmp/trunc.txt") . "\n";

// --- binary read ---

echo "\n=== Binary Read ===\n";

$fp = fopen("$tmp/stream.txt", 'r');
$chunk = fread($fp, 6);
echo "chunk: $chunk\n";
fclose($fp);

// --- glob ---

echo "\n=== Glob ===\n";

$files = glob("$tmp/*.txt");
sort($files);
echo "txt files: " . count($files) . "\n";
foreach ($files as $f) {
    echo "  " . basename($f) . "\n";
}

// --- scandir ---

echo "\n=== Scandir ===\n";

$entries = scandir($tmp);
$entries = array_filter($entries, function($e) { return $e !== '.' && $e !== '..'; });
sort($entries);
echo "entries: " . implode(', ', $entries) . "\n";

// --- cleanup ---

echo "\n=== Cleanup ===\n";

foreach (glob("$tmp/*") as $f) {
    unlink($f);
}
rmdir($tmp);
echo "cleaned: " . (file_exists($tmp) ? 'no' : 'yes') . "\n";

echo "\nDone.\n";
