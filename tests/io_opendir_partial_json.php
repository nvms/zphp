<?php
$dir = sys_get_temp_dir();
$path = "$dir/zphp_io2_" . getmypid();

// fread/fwrite cycle
$f = fopen($path, "w");
fwrite($f, "hello world\n");
fwrite($f, "second line\n");
fclose($f);

$f = fopen($path, "r");
echo fread($f, 5), "|\n"; // hello
echo fread($f, 100), "|\n"; // " world\nsecond line\n"
echo feof($f) ? "eof" : "no", "\n";
fclose($f);

// file_get_contents (binary safe)
file_put_contents($path, "abc\x00def\xff");
$d = file_get_contents($path);
echo strlen($d), "|", bin2hex($d), "\n"; // 7|6162630064656666 wait

// fopen 'a' mode
$f = fopen($path, "w"); fwrite($f, "AAA"); fclose($f);
$f = fopen($path, "a"); fwrite($f, "BBB"); fclose($f);
echo file_get_contents($path), "\n"; // AAABBB

// fseek SEEK_END
$f = fopen($path, "r");
fseek($f, 0, SEEK_END);
echo ftell($f), "\n"; // 6
fseek($f, -3, SEEK_END);
echo fread($f, 3), "|\n"; // BBB
fclose($f);

// fseek SEEK_CUR
$f = fopen($path, "r");
fseek($f, 2, SEEK_SET);
fseek($f, 1, SEEK_CUR);
echo ftell($f), ":", fread($f, 1), "|\n"; // 3:B
fclose($f);

// ftell after writes
$f = fopen($path, "w");
fwrite($f, "12345");
echo ftell($f), "\n"; // 5
fwrite($f, "67");
echo ftell($f), "\n"; // 7
fclose($f);

unlink($path);

// copy
$src = "$dir/zphp_copy_src_" . getmypid();
$dst = "$dir/zphp_copy_dst_" . getmypid();
file_put_contents($src, "data");
copy($src, $dst);
echo file_get_contents($dst), "\n";
unlink($src);
unlink($dst);

// rename
$a = "$dir/zphp_rename_a_" . getmypid();
$b = "$dir/zphp_rename_b_" . getmypid();
file_put_contents($a, "x");
rename($a, $b);
echo file_exists($a) ? "y" : "n", file_exists($b) ? "y" : "n", "\n"; // ny
echo file_get_contents($b), "\n";
unlink($b);

// scandir order
$d = "$dir/zphp_scandir_" . getmypid();
mkdir($d);
foreach (["c.txt", "a.txt", "b.txt"] as $f) file_put_contents("$d/$f", "");
$list = scandir($d);
$list = array_values(array_filter($list, fn($x) => $x !== "." && $x !== ".."));
sort($list);
foreach ($list as $f) echo "$f|";
echo "\n";

$rev = scandir($d, SCANDIR_SORT_DESCENDING);
$rev = array_values(array_filter($rev, fn($x) => $x !== "." && $x !== ".."));
foreach ($rev as $f) echo "$f|";
echo "\n";

// opendir/readdir
$dh = opendir($d);
$files = [];
while (($f = readdir($dh)) !== false) {
    if ($f === "." || $f === "..") continue;
    $files[] = $f;
}
closedir($dh);
sort($files);
foreach ($files as $f) echo "$f|";
echo "\n";

foreach (["a.txt", "b.txt", "c.txt"] as $f) unlink("$d/$f");
rmdir($d);

// chmod / fileperms
$p = "$dir/zphp_perms_" . getmypid();
file_put_contents($p, "");
chmod($p, 0644);
echo sprintf("%o", fileperms($p) & 0o777), "\n"; // 644
chmod($p, 0o600);
echo sprintf("%o", fileperms($p) & 0o777), "\n"; // 600
unlink($p);

// flock
$p = "$dir/zphp_flock_" . getmypid();
$f = fopen($p, "w");
echo flock($f, LOCK_EX) ? "y" : "n", "\n";
echo flock($f, LOCK_UN) ? "y" : "n", "\n";
fclose($f);
unlink($p);

// parse_url
print_r(parse_url("https://user:pass@host.example.com:8080/path/to/page?q=1&z=2#frag"));
echo parse_url("/just/path", PHP_URL_PATH), "\n";
echo parse_url("http://h/a?b=c", PHP_URL_HOST), "\n";
echo parse_url("http://h/a?b=c", PHP_URL_QUERY), "\n";
var_dump(parse_url("http://h/", PHP_URL_FRAGMENT));

// parse_str
parse_str("a=1&b[]=2&b[]=3&c[x]=hi", $r);
print_r($r);

// parse_ini_string
$ini = "[section]\nfoo=bar\nnum=42\n[other]\nlist[]=a\nlist[]=b\n";
print_r(parse_ini_string($ini, true));

// http_build_query
echo http_build_query(["a"=>1, "b"=>"x y", "c"=>["d","e"]]), "\n";
echo http_build_query(["a"=>1], "p_", "&", PHP_QUERY_RFC3986), "\n";

// json_decode with depth + assoc
$j = '{"a":{"b":{"c":1}}}';
print_r(json_decode($j, true, 5));
print_r(json_decode($j, true, 2));
echo json_last_error(), "\n";

// json_encode
echo json_encode([INF], JSON_PARTIAL_OUTPUT_ON_ERROR), "\n";
echo json_encode([1, 2, 3], JSON_PRETTY_PRINT|JSON_UNESCAPED_SLASHES), "\n";
echo json_encode(["a"=>1, "b"=>"<\"hi\">"], JSON_UNESCAPED_UNICODE), "\n";
