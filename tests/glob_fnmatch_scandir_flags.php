<?php
$dir = sys_get_temp_dir() . "/_zphp_glob_probe";
if (!is_dir($dir)) mkdir($dir, 0777, true);

foreach (["a.txt", "b.txt", "c.txt", "data.json", "image.png", "image.jpg", "config.yaml", "readme.md", "test.php"] as $f) {
    file_put_contents("$dir/$f", "");
}

mkdir("$dir/sub", 0777, true);
file_put_contents("$dir/sub/nested.txt", "");
file_put_contents("$dir/sub/inner.php", "");

$txt = glob("$dir/*.txt");
sort($txt);
print_r(array_map(fn($p) => basename($p), $txt));

$png = glob("$dir/*.png");
print_r(array_map(fn($p) => basename($p), $png));

$any = glob("$dir/*");
sort($any);
print_r(array_map(fn($p) => basename($p), $any));

$starts_i = glob("$dir/i*");
sort($starts_i);
print_r(array_map(fn($p) => basename($p), $starts_i));

$single_char = glob("$dir/?.txt");
sort($single_char);
print_r(array_map(fn($p) => basename($p), $single_char));

$bracket = glob("$dir/[abc].txt");
sort($bracket);
print_r(array_map(fn($p) => basename($p), $bracket));

$bracket2 = glob("$dir/[a-c].txt");
sort($bracket2);
print_r(array_map(fn($p) => basename($p), $bracket2));

$nope = glob("$dir/*.xml");
print_r($nope);

$brace = glob("$dir/{a,b}.txt", GLOB_BRACE);
sort($brace);
print_r(array_map(fn($p) => basename($p), $brace));

$brace2 = glob("$dir/image.{png,jpg}", GLOB_BRACE);
sort($brace2);
print_r(array_map(fn($p) => basename($p), $brace2));

echo fnmatch("*.txt", "test.txt") ? "y" : "n", "\n";
echo fnmatch("*.txt", "test.json") ? "y" : "n", "\n";
echo fnmatch("a*", "abc") ? "y" : "n", "\n";
echo fnmatch("a*", "ABC") ? "y" : "n", "\n";
echo fnmatch("a*", "ABC", FNM_CASEFOLD) ? "y" : "n", "\n";
echo fnmatch("file?.txt", "file1.txt") ? "y" : "n", "\n";
echo fnmatch("file?.txt", "file10.txt") ? "y" : "n", "\n";
echo fnmatch("[abc]", "a") ? "y" : "n", "\n";
echo fnmatch("[abc]", "d") ? "y" : "n", "\n";
echo fnmatch("[a-z]", "m") ? "y" : "n", "\n";
echo fnmatch("[a-z]", "M") ? "y" : "n", "\n";
echo fnmatch("[a-z]", "M", FNM_CASEFOLD) ? "y" : "n", "\n";

echo fnmatch("hello.txt", "hello.txt") ? "y" : "n", "\n";
echo fnmatch("hello.txt", "hello.json") ? "y" : "n", "\n";
echo fnmatch("", "") ? "y" : "n", "\n";

echo fnmatch("*", "anything") ? "y" : "n", "\n";

echo fnmatch("path/*.txt", "path/file.txt") ? "y" : "n", "\n";
echo fnmatch("path/*.txt", "other/file.txt") ? "y" : "n", "\n";

$entries = scandir($dir);
sort($entries);
print_r(array_values(array_filter($entries, fn($x) => $x !== "." && $x !== "..")));

$entries = scandir($dir, SCANDIR_SORT_DESCENDING);
print_r(array_values(array_filter($entries, fn($x) => $x !== "." && $x !== "..")));

$entries = scandir($dir, SCANDIR_SORT_NONE);
$entries = array_values(array_filter($entries, fn($x) => $x !== "." && $x !== ".."));
echo count($entries), "\n";

$txt2 = glob("$dir/*.txt");
echo count($txt2), "\n";

$onlyDir = glob("$dir/*", GLOB_ONLYDIR);
print_r(array_map(fn($p) => basename($p), $onlyDir));

$nosort = glob("$dir/*.txt", GLOB_NOSORT);
echo count($nosort), "\n";

$noescape = glob("$dir/*.txt", GLOB_NOESCAPE);
echo count($noescape), "\n";

echo fnmatch("a?c", "abc") ? "y" : "n", "\n";
echo fnmatch("a?c", "abbc") ? "y" : "n", "\n";

echo fnmatch("a*c", "abc") ? "y" : "n", "\n";
echo fnmatch("a*c", "abbc") ? "y" : "n", "\n";
echo fnmatch("a*c", "abxc") ? "y" : "n", "\n";
echo fnmatch("a*c", "axxxc") ? "y" : "n", "\n";

echo fnmatch(".*", ".hidden") ? "y" : "n", "\n";
echo fnmatch(".*", "visible") ? "y" : "n", "\n";

foreach (glob("$dir/sub/*") as $f) @unlink($f);
rmdir("$dir/sub");
foreach (glob("$dir/*") as $f) if (!is_dir($f)) @unlink($f);
rmdir($dir);
echo "cleaned\n";
