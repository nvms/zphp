<?php
$dir = sys_get_temp_dir() . "/zphp_fm_test_dir";
@mkdir($dir);
for ($i = 0; $i < 3; $i++) file_put_contents("$dir/f$i.txt", "data $i");

$it = new DirectoryIterator($dir);
$names = [];
foreach ($it as $entry) {
    if (!$entry->isDot()) $names[] = $entry->getFilename();
}
sort($names);
print_r($names);

$it = new DirectoryIterator($dir);
$dot_count = 0;
$non_dot = 0;
foreach ($it as $entry) {
    if ($entry->isDot()) $dot_count++;
    else $non_dot++;
}
echo $dot_count, " ", $non_dot, "\n";

$it = new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS);
$found = [];
foreach ($it as $e) $found[] = $e->getFilename();
sort($found);
print_r($found);

$tmp = tempnam(sys_get_temp_dir(), "zphp_mt_");
file_put_contents($tmp, "hello world");
echo mime_content_type($tmp), "\n";
unlink($tmp);

$tmp = tempnam(sys_get_temp_dir(), "zphp_mt_");
file_put_contents($tmp, "<?xml version=\"1.0\"?><root/>");
echo mime_content_type($tmp), "\n";
unlink($tmp);

$tmp = tempnam(sys_get_temp_dir(), "zphp_mt_");
file_put_contents($tmp, "\xff\xd8\xff\xe0\x00\x10JFIF");
echo mime_content_type($tmp), "\n";
unlink($tmp);

foreach (glob("$dir/*") as $f) unlink($f);
rmdir($dir);
