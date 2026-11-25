<?php
// opendir() and scandir() read glob:// as php's glob stream: the base names
// of the matches, relative patterns from the working directory
$dir = sys_get_temp_dir() . '/zphp_glob_wrapper_' . getmypid();
@mkdir($dir);
@mkdir("$dir/sub");
foreach (['b.txt', 'a.txt', 'c.log'] as $f) touch("$dir/$f");
touch("$dir/sub/inner.txt");
$old = getcwd();
chdir($dir);
var_dump(scandir('glob://*.txt'));
var_dump(scandir('glob://*.txt', SCANDIR_SORT_DESCENDING));
var_dump(scandir('glob://sub/*'));
var_dump(scandir('glob://nothing*'));
$h = opendir('glob://*');
$seen = [];
while (($e = readdir($h)) !== false) $seen[] = $e;
closedir($h);
var_dump($seen);
chdir($old);
foreach (['b.txt', 'a.txt', 'c.log', 'sub/inner.txt'] as $f) unlink("$dir/$f");
rmdir("$dir/sub");
rmdir($dir);
