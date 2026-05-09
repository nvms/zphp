<?php
// array_keys
$arr = ["a" => 1, "b" => 2, "c" => 1, "d" => 3, "e" => 1];
print_r(array_keys($arr));
print_r(array_keys($arr, 1));
print_r(array_keys($arr, "1", false)); // loose: matches int 1
print_r(array_keys($arr, "1", true));  // strict: no match

// array_values
print_r(array_values(["a" => 1, "b" => 2, "c" => 3]));
print_r(array_values([10 => "x", 20 => "y"])); // 0,1 keys

// array_reverse preserve
print_r(array_reverse([1,2,3]));
print_r(array_reverse([1,2,3], true));
print_r(array_reverse(["a"=>1, "b"=>2, "c"=>3]));
print_r(array_reverse(["a"=>1, "b"=>2, "c"=>3], true));

// array_slice
print_r(array_slice([1,2,3,4,5], 1, 3)); // 2,3,4
print_r(array_slice([1,2,3,4,5], -2)); // 4,5
print_r(array_slice([1,2,3,4,5], 1, 3, true)); // preserve numeric keys
print_r(array_slice(["a"=>1,"b"=>2,"c"=>3,"d"=>4], 1, 2));

// array_map with null callback (zip)
print_r(array_map(null, [1,2,3], ['a','b','c']));
print_r(array_map(null, [1,2], [3,4], [5,6]));

// array_fill
print_r(array_fill(0, 3, "x"));
print_r(array_fill(5, 3, "x"));
print_r(array_fill(-2, 3, "x"));

// array_fill_keys
print_r(array_fill_keys(["a", "b", "c"], 0));
print_r(array_fill_keys([1, 2, 3], "default"));

// range
print_r(range('a', 'e'));
print_r(range('a', 'k', 2));
print_r(range(1, 10, 2));
print_r(range(10, 1, -2));
print_r(range(1.0, 2.0, 0.25));
print_r(range(5, 5));

// str_pad type coercion
echo str_pad((string)5, 5, "0", STR_PAD_LEFT), "|\n";
echo str_pad("42", 5), "|\n"; // default pad with space, right
echo str_pad("ok", 1, " "), "|\n"; // smaller len returns original

// array_sum
echo array_sum([1, 2, 3]), "\n";
echo array_sum(["1", "2", "3"]), "\n"; // 6
// array_sum with non-numeric string emits PHP warning (architectural gap)
echo array_sum([1, 2.5, 3]), "\n"; // 6.5
echo array_sum([]), "\n";

// array_product
echo array_product([2, 3, 4]), "\n";
echo array_product([1.5, 2]), "\n";
echo array_product([]), "\n"; // 1
echo array_product([0, 5, 10]), "\n"; // 0

// path utilities
echo basename("/foo/bar/baz.txt"), "\n";
echo basename("/foo/bar/"), "\n"; // "bar"
echo basename("baz.txt", ".txt"), "\n"; // "baz"
echo basename("baz.txt", ".png"), "\n"; // "baz.txt"
echo dirname("/foo/bar/baz.txt"), "\n";
echo dirname("/foo/bar/baz.txt", 2), "\n"; // /foo
echo dirname("baz.txt"), "\n"; // .
echo dirname("/"), "\n"; // /

// pathinfo
print_r(pathinfo("/path/to/file.tar.gz"));
print_r(pathinfo("/path/to/file"));
print_r(pathinfo("file.txt", PATHINFO_EXTENSION));
print_r(pathinfo("file.txt", PATHINFO_FILENAME));
print_r(pathinfo("/no.ext/file"));

// realpath
$tmp = tempnam(sys_get_temp_dir(), "zphp_real");
echo realpath($tmp) === $tmp ? "real-eq\n" : "real-neq\n";
unlink($tmp);
var_dump(realpath("/nonexistent/path/here"));

// glob basics
$dir = sys_get_temp_dir() . "/zphp_glob_test_" . getmypid();
mkdir($dir);
file_put_contents("$dir/a.txt", "");
file_put_contents("$dir/b.txt", "");
file_put_contents("$dir/c.log", "");
$txt = glob("$dir/*.txt");
sort($txt);
foreach ($txt as $f) echo basename($f), "|";
echo "\n";
$all = glob("$dir/*");
sort($all);
foreach ($all as $f) echo basename($f), "|";
echo "\n";
$nope = glob("$dir/*.nope");
echo count($nope), "\n";
unlink("$dir/a.txt"); unlink("$dir/b.txt"); unlink("$dir/c.log");
rmdir($dir);

// is_dir/is_file/file_exists
$f = tempnam(sys_get_temp_dir(), "zphp_is");
echo is_file($f) ? "f" : "n", "\n";
echo is_dir($f) ? "d" : "n", "\n";
echo file_exists($f) ? "e" : "n", "\n";
unlink($f);
echo file_exists($f) ? "e" : "n", "\n";

// dirname trim trailing slash
echo dirname("/a/b/c/"), "\n"; // /a/b
echo dirname("/a/"), "\n"; // /
