<?php
$dir = sys_get_temp_dir() . "/zphp_glob_test";
@mkdir($dir);
file_put_contents("$dir/a.txt", "");
file_put_contents("$dir/b.txt", "");
file_put_contents("$dir/c.log", "");
file_put_contents("$dir/.hidden", "");
@mkdir("$dir/sub");
file_put_contents("$dir/sub/d.txt", "");

// scandir
print_r(scandir($dir));
print_r(scandir($dir, SCANDIR_SORT_DESCENDING));
print_r(scandir($dir, SCANDIR_SORT_NONE));

// glob
$g = glob("$dir/*.txt");
sort($g); print_r(array_map('basename', $g));
$g = glob("$dir/[a-z].txt");
sort($g); print_r(array_map('basename', $g));
$g = glob("$dir/*", GLOB_MARK);
sort($g); print_r(array_map('basename', $g));
$g = glob("$dir/*", GLOB_ONLYDIR);
sort($g); print_r(array_map('basename', $g));

// fnmatch
var_dump(fnmatch("*.txt", "hello.txt"));
var_dump(fnmatch("*.txt", "hello.log"));
var_dump(fnmatch("[ab]?", "a1"));
var_dump(fnmatch("[ab]?", "c1"));
var_dump(fnmatch("file.[!ch]*", "file.txt"));
var_dump(fnmatch("file.[!ch]*", "file.c"));
var_dump(fnmatch("FOO", "foo", FNM_CASEFOLD));
var_dump(fnmatch("FOO", "foo"));
var_dump(fnmatch("/path/file", "/path/file", FNM_PATHNAME));
var_dump(fnmatch(".hidden", ".hidden", FNM_PERIOD));
var_dump(fnmatch("?hidden", ".hidden", FNM_PERIOD));

// fileperms
echo decoct(fileperms($dir)), "\n";
echo decoct(fileperms("$dir/a.txt") & 0777), "\n";

// cleanup
unlink("$dir/a.txt");
unlink("$dir/b.txt");
unlink("$dir/c.log");
unlink("$dir/.hidden");
unlink("$dir/sub/d.txt");
rmdir("$dir/sub");
rmdir($dir);
echo "cleanup done\n";
