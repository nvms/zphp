<?php
$dir = sys_get_temp_dir() . "/zphp_dir_test";
@mkdir($dir);
file_put_contents("$dir/a.txt", "1");
file_put_contents("$dir/b.txt", "2");
file_put_contents("$dir/c.log", "3");
file_put_contents("$dir/data.json", "4");
mkdir("$dir/sub");
file_put_contents("$dir/sub/nested.txt", "5");

// scandir
$entries = scandir($dir);
sort($entries);
print_r($entries);

// scandir SORT_DESC
$entries = scandir($dir, SCANDIR_SORT_DESCENDING);
print_r($entries);

// scandir on nonexistent (return false; suppress warning)
$r = @scandir("/nonexistent/path/zphp_xx");
var_dump($r);

// glob
$matches = glob("$dir/*.txt");
sort($matches);
foreach ($matches as $m) echo basename($m), " ";
echo "\n";

$matches = glob("$dir/*.{txt,log}", GLOB_BRACE);
sort($matches);
foreach ($matches as $m) echo basename($m), " ";
echo "\n";

// glob - directory only
$matches = glob("$dir/*", GLOB_ONLYDIR);
foreach ($matches as $m) echo basename($m), " ";
echo "\n";

// glob nonexistent
$matches = glob("$dir/zzzzzz_no_*.xxx");
print_r($matches);

// opendir/readdir/closedir
$d = opendir($dir);
$found = [];
while (($e = readdir($d)) !== false) {
    $found[] = $e;
}
closedir($d);
sort($found);
print_r($found);

// rewinddir
$d = opendir($dir);
$count1 = 0;
while (readdir($d) !== false) $count1++;
rewinddir($d);
$count2 = 0;
while (readdir($d) !== false) $count2++;
closedir($d);
echo $count1, "/", $count2, "\n";

// basename
echo basename("/path/to/file.txt"), "\n";
echo basename("/path/to/file.txt", ".txt"), "\n";
echo basename("/path/to/dir/"), "\n";
echo basename("filename.ext"), "\n";
echo basename(""), "\n";
echo basename("/"), "\n";
echo basename("/path/file.tar.gz", ".gz"), "\n";

// dirname
echo dirname("/path/to/file.txt"), "\n";
echo dirname("/path/to/dir/"), "\n";
echo dirname("filename"), "\n";
echo dirname("/file"), "\n";
echo dirname("/"), "\n";
echo dirname(""), "\n";
echo dirname("/a/b/c", 2), "\n";
echo dirname("/a/b/c", 3), "\n";

// pathinfo
print_r(pathinfo("/path/to/file.txt"));
print_r(pathinfo("file.tar.gz"));
print_r(pathinfo("/path/no_ext"));
print_r(pathinfo("/path/.hidden")); // ext is hidden? PHP: dirname=/path, basename=.hidden, filename=
print_r(pathinfo("/path/.hidden.txt"));

// pathinfo with options
echo pathinfo("/path/file.txt", PATHINFO_DIRNAME), "\n";
echo pathinfo("/path/file.txt", PATHINFO_BASENAME), "\n";
echo pathinfo("/path/file.txt", PATHINFO_EXTENSION), "\n";
echo pathinfo("/path/file.txt", PATHINFO_FILENAME), "\n";

// pathinfo no extension
echo pathinfo("/path/no_ext", PATHINFO_EXTENSION) ?? "null", "\n";
$pi = pathinfo("/path/no_ext");
var_dump(isset($pi["extension"]));

// realpath
$realdir = realpath($dir);
echo $realdir === $dir ? "same" : "different", "\n";
echo realpath("$dir/a.txt") === "$dir/a.txt" ? "y" : "n", "\n";
var_dump(realpath("/nonexistent/zphp/xxx"));

// file_exists
var_dump(file_exists("$dir/a.txt"));
var_dump(file_exists($dir));
var_dump(file_exists("/nonexistent/zphp/xxx"));

// is_file vs is_dir
var_dump(is_file("$dir/a.txt"));
var_dump(is_file($dir));
var_dump(is_dir($dir));
var_dump(is_dir("$dir/a.txt"));

// filesize / filetype
echo filesize("$dir/a.txt"), "\n";
echo filetype("$dir/a.txt"), "\n"; // file
echo filetype($dir), "\n";          // dir

// stat
$s = stat("$dir/a.txt");
echo gettype($s), "\n";
echo isset($s["size"]) && $s["size"] === 1 ? "size-ok" : "size-bad", "\n";
echo isset($s["mtime"]) ? "has-mtime" : "no", "\n";

// tempnam / sys_get_temp_dir
$t = tempnam(sys_get_temp_dir(), "zphp_");
echo file_exists($t) ? "y" : "n", "\n";
unlink($t);

// is_readable/writable
var_dump(is_readable("$dir/a.txt"));
var_dump(is_writable("$dir/a.txt"));
var_dump(is_readable("/nonexistent/path/zz"));

// rmdir cleanup - empty dir
unlink("$dir/sub/nested.txt");
rmdir("$dir/sub");
unlink("$dir/a.txt");
unlink("$dir/b.txt");
unlink("$dir/c.log");
unlink("$dir/data.json");
rmdir($dir);

// after cleanup
var_dump(file_exists($dir));
