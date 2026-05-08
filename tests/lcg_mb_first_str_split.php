<?php
// lcg_value
$v = @lcg_value();
var_dump(is_float($v) && $v >= 0 && $v < 1);

// mb_ucfirst / mb_lcfirst on multibyte
echo mb_ucfirst("héllo"), "\n";
echo mb_lcfirst("ÉTAGE"), "\n";
echo mb_ucfirst("abc"), "\n";
echo mb_lcfirst("ABC"), "\n";
echo mb_ucfirst(""), "\n";
echo mb_lcfirst(""), "\n";

// regular ucfirst/lcfirst stay ASCII-only
echo ucfirst("hello"), "\n";
echo ucfirst("héllo"), "\n";  // h → H, but é stays (because it's a multibyte char, not the first byte)
echo lcfirst("HELLO"), "\n";
echo lcfirst("ÉTAGE"), "\n";  // É not lowercased

// str_split with empty input returns empty array
$r = str_split("", 1);
var_dump($r);
$r = str_split("");
var_dump($r);
print_r(str_split("abcd", 2));
print_r(str_split("abcd", 3));

// hash raw_output roundtrip
echo bin2hex(hash('md5', 'abc', true)), "\n";
echo hash('md5', 'abc'), "\n";
echo bin2hex(hash('sha1', 'abc', true)), "\n";
echo hash('sha1', 'abc'), "\n";
echo bin2hex(hash('sha256', 'abc', true)), "\n";
echo hash('sha256', 'abc'), "\n";
echo bin2hex(hash_hmac('sha256', 'data', 'key', true)), "\n";
echo hash_hmac('sha256', 'data', 'key'), "\n";

// str_replace count parameter
$count = 0;
echo str_replace('a', 'X', 'banana', $count), " count=", $count, "\n";
$count = 0;
echo str_replace(['a', 'b'], ['1', '2'], 'banana', $count), " count=", $count, "\n";
$count = 0;
echo str_replace('z', 'Z', 'banana', $count), " count=", $count, "\n";

// ksort SORT_NATURAL
$a = ['file10' => 1, 'file2' => 2, 'file1' => 3];
ksort($a, SORT_NATURAL); print_r($a);
$b = ['IMG10' => 1, 'img2' => 2, 'IMG1' => 3];
ksort($b, SORT_NATURAL | SORT_FLAG_CASE); print_r($b);
