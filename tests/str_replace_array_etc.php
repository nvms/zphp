<?php
$pct = 0;
$r = similar_text("hello", "hello", $pct);
echo "$r $pct\n";
$pct = 0;
$r = similar_text("hello", "world", $pct);
echo "$r $pct\n";
$pct = 0;
$r = similar_text("", "", $pct);
echo "$r $pct\n";
$pct = 0;
$r = similar_text("aa", "ab", $pct);
echo "$r $pct\n";

echo levenshtein("kitten", "sitting"), "\n";
echo levenshtein("a", "b"), "\n";
echo levenshtein("", "abc"), "\n";
echo levenshtein("abc", ""), "\n";
echo levenshtein("kitten", "sitting", 1, 2, 1), "\n";
echo levenshtein("aa", "bb", 0, 0, 0), "\n";

$count = 0;
$r = str_replace(["a", "b"], ["x", "y"], ["aaa", "bbb", "ab"], $count);
print_r($r); echo "count=$count\n";
$count = 0;
$r = str_replace(["a", "b"], "X", ["aaa", "bbb"], $count);
print_r($r); echo "count=$count\n";
$count = 0;
$r = str_replace("a", "X", ["aXX", "bb", "aaa"], $count);
print_r($r); echo "count=$count\n";

try { array_chunk([1, 2, 3], 0); } catch (ValueError $e) { echo "vchunk0\n"; }
try { array_chunk([1, 2, 3], -1); } catch (ValueError $e) { echo "vchunkneg\n"; }

try { array_combine([1, 2], ["a", "b", "c"]); } catch (ValueError $e) { echo "vcombine\n"; }
print_r(array_combine([], []));

$a = ["a" => 1, "b" => 2, "c" => 3];
print_r(array_filter($a, fn($v) => $v > 1));
print_r(array_filter($a, fn($k) => $k !== "b", ARRAY_FILTER_USE_KEY));
print_r(array_filter($a, fn($v, $k) => $v > 1 && $k !== "c", ARRAY_FILTER_USE_BOTH));

echo array_reduce([1, 2, 3, 4], fn($c, $i) => $c + $i, 0), "\n";
echo array_reduce([1, 2, 3], fn($c, $i) => $c . $i, "x"), "\n";
echo array_reduce([], fn($a, $b) => $a, 99), "\n";

class Row { public function __construct(public int $id, public string $name) {} }
$rows = [new Row(1, "x"), new Row(2, "y"), new Row(3, "z")];
print_r(array_column($rows, "name"));
print_r(array_column($rows, "name", "id"));
print_r(array_column($rows, null, "id"));

$out = preg_replace_callback_array([
    '/\d+/' => fn($m) => "[N:$m[0]]",
    '/[A-Z]+/' => fn($m) => "[U:$m[0]]",
], "abc123XYZ45");
echo $out, "\n";

preg_match('/(?<year>\d{4})-(?<month>\d{2})/', '2024-06', $m);
print_r($m);
preg_match('/(?P<word>\w+)/', 'hello world', $m);
print_r($m);

echo hash("md5", "hello"), "\n";
echo hash("sha256", "hello"), "\n";
echo strlen(hash("sha256", "", true)), "\n";

echo base64_encode("hello\nworld"), "\n";
echo base64_decode("aGVsbG8gd29ybGQ="), "\n";
echo base64_decode("aGVsbG8\n gd29ybGQ="), "\n";
var_dump(base64_decode("invalid!", true));

print_r(str_getcsv('a,b,c', escape: ""));
print_r(str_getcsv('"a","b,c","d"', escape: ""));
print_r(str_getcsv("a;b;c", ";", escape: ""));
print_r(str_getcsv('"a","quoted ""b""","c"', escape: ""));
print_r(str_getcsv("a\nb,c", escape: ""));

print_r(parse_ini_string("k=v\na=1"));
print_r(parse_ini_string("[s1]\nk=v\n[s2]\nk=z", true));
print_r(parse_ini_string("k=true\nb=false\nc=null", false, INI_SCANNER_TYPED));
print_r(parse_ini_string('k = "hello world"' . "\n" . 'n = 42'));

print_r(array_map(fn($x) => $x*2, ["a"=>1,"b"=>2,"c"=>3]));

print_r(str_split(""));
print_r(str_split("abc"));
print_r(str_split("abcde", 2));
print_r(str_split("abc", 10));
