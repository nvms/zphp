<?php
$tmp = sys_get_temp_dir() . "/zphp_io_test";
@mkdir($tmp);

// file_put_contents flags
file_put_contents("$tmp/a.txt", "hello");
file_put_contents("$tmp/a.txt", " world", FILE_APPEND);
echo file_get_contents("$tmp/a.txt"), "\n";

// FILE_APPEND with LOCK_EX
file_put_contents("$tmp/b.txt", "line1\n");
file_put_contents("$tmp/b.txt", "line2\n", FILE_APPEND | LOCK_EX);
echo file_get_contents("$tmp/b.txt"), "\n";

// file_get_contents with offset/length
file_put_contents("$tmp/c.txt", "0123456789ABCDEF");
echo file_get_contents("$tmp/c.txt", false, null, 4), "|\n";    // from offset 4: "456789ABCDEF"
echo file_get_contents("$tmp/c.txt", false, null, 4, 6), "|\n"; // 6 bytes from offset 4: "456789"
echo file_get_contents("$tmp/c.txt", false, null, 0, 5), "|\n"; // first 5: "01234"
echo file_get_contents("$tmp/c.txt", false, null, -3), "|\n";   // last 3: "DEF"

// fgets edge cases
file_put_contents("$tmp/lines.txt", "line1\nline2\nline3");  // no trailing newline
$f = fopen("$tmp/lines.txt", "r");
while (!feof($f)) echo "[" . fgets($f) . "]\n";
fclose($f);

// binary data with NUL bytes
$nul_data = "abc\x00def\x00ghi";
file_put_contents("$tmp/bin.dat", $nul_data);
$read = file_get_contents("$tmp/bin.dat");
echo strlen($read) === 11 ? "binsafe" : "binbroken", "\n";
echo bin2hex($read), "\n";

// fread/fwrite binary
$f = fopen("$tmp/bin2.dat", "wb");
fwrite($f, "abc\x00\x01\x02def");
fclose($f);
$f = fopen("$tmp/bin2.dat", "rb");
$data = fread($f, 100);
fclose($f);
echo bin2hex($data), "\n";
echo strlen($data), "\n";

// stream_copy_to_stream
$src = fopen("$tmp/bin2.dat", "rb");
$dst = fopen("$tmp/copy.dat", "wb");
$n = stream_copy_to_stream($src, $dst);
echo "copied=$n\n";
fclose($src);
fclose($dst);
echo bin2hex(file_get_contents("$tmp/copy.dat")), "\n";

// tmpfile
$tmp_f = tmpfile();
fwrite($tmp_f, "tmp data");
rewind($tmp_f);
echo fread($tmp_f, 100), "\n";
$meta = stream_get_meta_data($tmp_f);
echo isset($meta['uri']) ? "has-uri\n" : "no-uri\n";
fclose($tmp_f);

// sys_get_temp_dir
$t = sys_get_temp_dir();
echo $t === "" ? "empty\n" : "non-empty\n";

// fprintf
$f = fopen("$tmp/fmt.txt", "w");
fprintf($f, "%s=%d\n", "n", 42);
fprintf($f, "[%.2f]", 3.14);
fclose($f);
echo file_get_contents("$tmp/fmt.txt"), "\n";

// fputs is alias for fwrite
$f = fopen("$tmp/alias.txt", "w");
$n = fputs($f, "alias-test");
fclose($f);
echo $n, ":", file_get_contents("$tmp/alias.txt"), "\n";

// dechex/decoct with negatives
echo dechex(-1), "\n";  // "ffffffffffffffff" (depends on platform - 64-bit)
echo dechex(-256), "\n";
echo decoct(-1), "\n";
echo decbin(-1), "\n";

// sprintf %s with __toString object
class Money { public function __construct(public int $amount) {} public function __toString(): string { return "$" . $this->amount; } }
echo sprintf("price=%s", new Money(50)), "\n";
echo sprintf("(%s)", new Money(100)), "\n";
echo "implicit=" . new Money(25) . "\n";

// sprintf with array argument
echo @sprintf("%d", [1,2,3]), "|\n"; // PHP warns + "1"

// str_pad with multibyte fill char (byte mode, broken)
echo str_pad("ab", 10, "ø"), "|\n"; // ø is 2 bytes; pad fills bytes
// mb_str_pad with multibyte
echo mb_str_pad("abc", 8, "ø"), "|\n";
echo mb_str_pad("abc", 8, "ø", STR_PAD_LEFT), "|\n";
echo mb_str_pad("abc", 8, "ø", STR_PAD_BOTH), "|\n";
echo mb_str_pad("café", 6, "*"), "|\n";

// array_combine with int+float keys
$a = array_combine([1, 1.5, 2], ["a", "b", "c"]);
print_r($a);

// array_flip with mixed keys
$a = ["a" => 1, "b" => 2, "c" => 1]; // collision: c flips to 1, overwriting "a"
print_r(array_flip($a));
print_r(array_flip([10, 20, 30, 10])); // index 0 and 3 both have value 10

// array_walk_recursive on objects (does NOT recurse into objects)
$data = ["a" => 1, "b" => (object)["x" => 10, "y" => 20], "c" => [3, 4]];
array_walk_recursive($data, function(&$v, $k) { if (is_int($v)) $v *= 2; });
print_r($data);

// cleanup
foreach (["a.txt","b.txt","c.txt","lines.txt","bin.dat","bin2.dat","copy.dat","fmt.txt","alias.txt"] as $f) @unlink("$tmp/$f");
@rmdir($tmp);
echo "done\n";
