<?php
// opening a missing directory warns as php's plain wrapper does, the dir
// functions warn when they fall back to the last opened directory, and a
// closed Directory refuses its methods
$missing = sys_get_temp_dir() . "/zphp_no_such_dir_" . "x";
var_dump(opendir($missing));
var_dump(dir($missing));
var_dump(scandir($missing));
var_dump(chdir($missing));
try {
    scandir("");
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}

$base = sys_get_temp_dir() . "/zphp_dir_open_failures";
@mkdir($base);
touch("$base/a.txt");
touch("$base/b.txt");
var_dump(scandir($base, PHP_INT_MAX), scandir($base, -5), scandir($base, SCANDIR_SORT_ASCENDING));

$h = opendir($base);
$names = [];
while (($n = readdir()) !== false) {
    $names[] = $n;
}
sort($names);
var_dump($names);
rewinddir();
closedir();

$d = dir($base);
$d->close();
try {
    $d->read();
} catch (Throwable $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
$r = new ReflectionClass("Directory");
var_dump($r->newInstanceWithoutConstructor());

unlink("$base/a.txt");
unlink("$base/b.txt");
rmdir($base);
