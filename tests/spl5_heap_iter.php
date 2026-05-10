<?php
// SplPriorityQueue iteration
$pq = new SplPriorityQueue();
$pq->insert("a", 5);
$pq->insert("b", 1);
$pq->insert("c", 10);
$pq->insert("d", 3);

// default extract: data only, in priority order (high first)
foreach ($pq as $v) echo "$v ";
echo "\n"; // c a d b (10, 5, 3, 1)

// SplMinHeap
$h = new SplMinHeap();
foreach ([7, 2, 9, 1, 5] as $v) $h->insert($v);
while (!$h->isEmpty()) echo $h->extract(), " ";
echo "\n"; // 1 2 5 7 9

// SplMaxHeap
$h = new SplMaxHeap();
foreach ([7, 2, 9, 1, 5] as $v) $h->insert($v);
while (!$h->isEmpty()) echo $h->extract(), " ";
echo "\n"; // 9 7 5 2 1

// custom heap
class StringLengthHeap extends SplHeap {
    protected function compare($a, $b): int { return strlen($a) - strlen($b); } // shorter first? no - max heap by length
}
$h = new StringLengthHeap();
$h->insert("a");
$h->insert("hello");
$h->insert("ab");
$h->insert("hi there!");
while (!$h->isEmpty()) echo $h->extract(), " ";
echo "\n";

// inverted compare
class ReverseHeap extends SplHeap {
    protected function compare($a, $b): int { return $b - $a; } // min via reverse
}
$h = new ReverseHeap();
foreach ([5, 1, 3, 7, 2] as $v) $h->insert($v);
while (!$h->isEmpty()) echo $h->extract(), " ";
echo "\n"; // 1 2 3 5 7

// SplFileObject CSV
$tmp = sys_get_temp_dir() . "/zphp_csv_" . getmypid() . ".csv";
file_put_contents($tmp, "name,age\nalice,30\nbob,25\ncarol,40\n");

$f = new SplFileObject($tmp, "r");
$f->setFlags(SplFileObject::READ_CSV);
foreach ($f as $row) {
    if ($row === [null] || $row === false) continue; // skip empty trailing
    print_r($row);
}
unlink($tmp);

// SplFileInfo getRealPath
$tmp = sys_get_temp_dir() . "/zphp_sfi_static";
file_put_contents($tmp, "");
$info = new SplFileInfo($tmp);
echo $info->getFilename(), "\n";
echo $info->getRealPath() !== false ? "real-set\n" : "false\n";
echo $info->getSize(), "\n";
echo $info->isFile() ? "f" : "d", "\n";
unlink($tmp);

// SplFileInfo getExtension
$info = new SplFileInfo("/path/file.txt");
echo $info->getExtension(), "\n"; // txt
echo $info->getBasename(), "\n";  // file.txt
echo $info->getBasename(".txt"), "\n"; // file

// RecursiveDirectoryIterator
$dir = sys_get_temp_dir() . "/zphp_rdi_" . getmypid();
mkdir($dir);
mkdir("$dir/sub");
file_put_contents("$dir/a.txt", "");
file_put_contents("$dir/b.txt", "");
file_put_contents("$dir/sub/c.txt", "");

$it = new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS);
$rii = new RecursiveIteratorIterator($it);
$files = [];
foreach ($rii as $f) {
    if ($f->isFile()) $files[] = $f->getFilename();
}
sort($files);
foreach ($files as $f) echo $f, "|";
echo "\n";

// cleanup
unlink("$dir/a.txt"); unlink("$dir/b.txt"); unlink("$dir/sub/c.txt");
rmdir("$dir/sub");
rmdir($dir);

// FilesystemIterator
$dir = sys_get_temp_dir() . "/zphp_fsi_" . getmypid();
mkdir($dir);
file_put_contents("$dir/x.txt", "");
file_put_contents("$dir/y.txt", "");
$it = new FilesystemIterator($dir);
$names = [];
foreach ($it as $f) $names[] = $f->getFilename();
sort($names);
foreach ($names as $n) echo "$n|";
echo "\n";
unlink("$dir/x.txt");
unlink("$dir/y.txt");
rmdir($dir);

// GlobIterator
$dir = sys_get_temp_dir() . "/zphp_gi_" . getmypid();
mkdir($dir);
file_put_contents("$dir/a.log", "");
file_put_contents("$dir/b.txt", "");
file_put_contents("$dir/c.log", "");

$gi = new GlobIterator("$dir/*.log");
$files = [];
foreach ($gi as $f) $files[] = $f->getFilename();
sort($files);
foreach ($files as $n) echo "$n|";
echo "\n";

unlink("$dir/a.log");
unlink("$dir/b.txt");
unlink("$dir/c.log");
rmdir($dir);
