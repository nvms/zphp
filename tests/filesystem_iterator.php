<?php
$d = sys_get_temp_dir() . '/zphp_fsi_t_' . uniqid();
mkdir($d);
file_put_contents("$d/a.txt", '');
file_put_contents("$d/b.txt", '');
file_put_contents("$d/c.php", '');
mkdir("$d/sub");
file_put_contents("$d/sub/d.txt", '');

// FilesystemIterator skips dots by default
$names = [];
foreach (new FilesystemIterator($d) as $f) {
    $names[] = $f->getFilename();
}
sort($names);
print_r($names);

// FilesystemIterator yields SplFileInfo
$it = new FilesystemIterator($d);
$it->rewind();
$f = $it->current();
var_dump($f instanceof SplFileInfo);

// GlobIterator filters by pattern
$names = [];
foreach (new GlobIterator("$d/*.txt") as $f) {
    $names[] = $f->getFilename();
}
sort($names);
print_r($names);

// GlobIterator with no matches
$names = [];
foreach (new GlobIterator("$d/*.xyz") as $f) {
    $names[] = $f->getFilename();
}
echo count($names), "\n";

// Recursive directory iteration
$rdi = new RecursiveDirectoryIterator($d, RecursiveDirectoryIterator::SKIP_DOTS);
$rii = new RecursiveIteratorIterator($rdi);
$names = [];
foreach ($rii as $f) {
    $names[] = $f->getFilename();
}
sort($names);
print_r($names);

// SplFileInfo basics
$fi = new SplFileInfo("$d/a.txt");
echo $fi->getFilename(), "\n";
var_dump($fi->isFile());
var_dump($fi->isDir());
echo $fi->getExtension(), "\n";

// cleanup
unlink("$d/sub/d.txt"); rmdir("$d/sub");
foreach (glob("$d/*") as $f) unlink($f);
rmdir($d);
