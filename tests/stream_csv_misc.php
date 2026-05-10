<?php
$dir = sys_get_temp_dir();
$path = "$dir/zphp_stream_" . getmypid();
file_put_contents($path, "hello world");

// stream_get_contents
$f = fopen($path, "r");
$content = stream_get_contents($f);
echo $content, "|\n"; // hello world
fclose($f);

// stream_get_contents with offset
$f = fopen($path, "r");
$content = stream_get_contents($f, -1, 6);
echo $content, "|\n"; // world
fclose($f);

// stream_get_contents with length
$f = fopen($path, "r");
$content = stream_get_contents($f, 5);
echo $content, "|\n"; // hello
fclose($f);

// php://memory
$f = fopen("php://memory", "w+");
fwrite($f, "abc");
rewind($f);
echo fread($f, 100), "|\n";
fclose($f);

// php://temp
$f = fopen("php://temp", "w+");
fwrite($f, "data");
rewind($f);
echo stream_get_contents($f), "|\n";
fclose($f);

// stream_set_blocking
$f = fopen($path, "r");
$ok = stream_set_blocking($f, false);
echo $ok ? "y" : "n", "\n";
$ok = stream_set_blocking($f, true);
echo $ok ? "y" : "n", "\n";
fclose($f);

// fputcsv default
$tmp = "$dir/zphp_csv_" . getmypid();
$f = fopen($tmp, "w");
fputcsv($f, ["a", "b", "c"], ",", '"', "");
fputcsv($f, ["x,y", 'with"quote', "normal"], ",", '"', "");
fclose($f);
echo file_get_contents($tmp);

// fputcsv with custom delim
$f = fopen($tmp, "w");
fputcsv($f, ["a", "b", "c"], ";", '"', "");
fputcsv($f, ["a;b", "c"], ";", '"', "");
fclose($f);
echo file_get_contents($tmp);

// fputcsv with custom enclosure
$f = fopen($tmp, "w");
fputcsv($f, ["a", "b", 'c"d'], ",", "'", "");
fclose($f);
echo file_get_contents($tmp);

// fputcsv escape
$f = fopen($tmp, "w");
// PHP 8.4 default escape changed; use explicit
fputcsv($f, ["abc", 'def\\'], ",", '"', "");
fclose($f);
echo file_get_contents($tmp);

// fgetcsv round-trip
$f = fopen($tmp, "w");
fputcsv($f, ["alice", "30", "engineer"], ",", '"', "");
fputcsv($f, ["bob", "25", 'has "quote"'], ",", '"', "");
fclose($f);

$f = fopen($tmp, "r");
while (($row = fgetcsv($f, 0, ",", '"', "")) !== false) {
    print_r($row);
}
fclose($f);
unlink($tmp);
unlink($path);

// str_getcsv
print_r(str_getcsv('alice,30,"engineer"', ",", '"', ""));
print_r(str_getcsv('a,"b,c",d', ",", '"', ""));
print_r(str_getcsv('a;b;"c""d"', ";", '"', ""));

// fopen with mode 'b' binary
$path = "$dir/zphp_bin_" . getmypid();
file_put_contents($path, "\x00\xff\x80\x01");
$f = fopen($path, "rb");
$d = fread($f, 100);
echo bin2hex($d), "\n"; // 00ff8001
fclose($f);
unlink($path);

// stream_get_meta_data
$path = "$dir/zphp_meta_" . getmypid();
file_put_contents($path, "x");
$f = fopen($path, "r");
$meta = stream_get_meta_data($f);
echo gettype($meta), "\n";
echo isset($meta["mode"]) ? "mode-set" : "no", "\n";
fclose($f);
unlink($path);

// fpassthru
$path = "$dir/zphp_pt_" . getmypid();
file_put_contents($path, "passthru-data");
$f = fopen($path, "r");
ob_start();
fpassthru($f);
$out = ob_get_clean();
echo $out, "|\n";
fclose($f);
unlink($path);
