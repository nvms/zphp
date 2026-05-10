<?php
// array_chunk with mixed keys
$arr = ["a" => 1, "b" => 2, 3, 4, "c" => 5];
print_r(array_chunk($arr, 2));
print_r(array_chunk($arr, 2, true));
print_r(array_chunk(["a"=>1, "b"=>2], 5, true));

// str_split multibyte (byte-level for str_split)
print_r(str_split("héllo", 2));
print_r(str_split("héllo", 1));
try { str_split("abc", -1); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }
try { str_split("abc", 0); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

// substr_count with offset/length
echo substr_count("aaaaa", "aa"), "\n"; // 2
echo substr_count("aaaaa", "aa", 1), "\n"; // 2 (skip first char)
echo substr_count("aaaaa", "aa", 0, 3), "\n"; // 1 (only 3 chars)
echo substr_count("aaaa", "aa", 0, 4), "\n"; // 2
try { substr_count("abc", "aa", 0, 100); echo "no\n"; } catch (\ValueError $e) { echo "ve\n"; }

// parse_str nested
parse_str("a[b][c]=1&a[b][d]=2&x[]=1&x[]=2", $r);
print_r($r);

parse_str("first=name&last=str&%5Ba%5D=1", $r);
print_r($r);

parse_str("foo[bar][baz]=v", $r);
print_r($r);

parse_str("a=1&b=2&a=3", $r); // duplicate key
print_r($r);

// http_build_query encoding
echo http_build_query(["a" => "x y"]), "\n"; // a=x+y
echo http_build_query(["a" => "x y"], "", "&", PHP_QUERY_RFC3986), "\n"; // a=x%20y
echo http_build_query(["a" => "/?:@&=+$,;"]), "\n"; // various encoded
echo http_build_query(["a" => "/?:@&=+$,;"], "", "&", PHP_QUERY_RFC3986), "\n";

echo urlencode("hello world+&=?"), "\n"; // hello+world%2B%26%3D%3F
echo rawurlencode("hello world+&=?"), "\n"; // hello%20world%2B%26%3D%3F
echo urlencode("a~b.c-d_e!*'()"), "\n"; // tilde encoded? - PHP encodes !
echo rawurlencode("a~b.c-d_e!*'()"), "\n"; // tilde NOT encoded by rawurlencode

// fdiv NaN/Inf
echo fdiv(1, 0), "\n"; // INF
echo fdiv(-1, 0), "\n"; // -INF
echo is_nan(fdiv(0, 0)) ? "nan\n" : "no\n";
echo is_infinite(fdiv(1, 0)) ? "inf\n" : "no\n";
echo is_nan(fdiv(INF, INF)) ? "nan\n" : "no\n";
echo fdiv(INF, 1), "\n"; // INF

// pow with negatives
echo (-2) ** 3, "\n"; // -8
echo (-2) ** 4, "\n"; // 16
echo pow(-2, 3), "\n"; // -8
echo is_nan(pow(-8, 1/3)) ? "nan\n" : "ok\n";
echo pow(0, 0), "\n"; // 1
echo 2 ** 0.5, "\n"; // sqrt(2)

// base_convert large
echo base_convert("ffffffffff", 16, 10), "\n"; // 1099511627775
echo base_convert("1099511627775", 10, 16), "\n"; // ffffffffff
echo base_convert("999999999999999", 10, 36), "\n"; // some base36

// base_convert("-ff", ...) returns 255 in both; PHP emits a deprecation warning we don't replicate

// bin2hex/hex2bin large
$big = str_repeat("\x00\xff", 100);
$h = bin2hex($big);
echo strlen($h), "\n"; // 400
$r = hex2bin($h);
echo $r === $big ? "rt-ok\n" : "rt-fail\n";

// base64 large
$big = random_bytes(1024);
$enc = base64_encode($big);
$dec = base64_decode($enc);
echo $dec === $big ? "b64-rt-ok\n" : "no\n";

// uniqid format
$id1 = uniqid();
$id2 = uniqid();
echo $id1 !== $id2 ? "diff\n" : "same\n";
echo strlen($id1) >= 13 ? "len-ok\n" : "no\n";
$id3 = uniqid("p_");
echo strpos($id3, "p_") === 0 ? "prefix-ok\n" : "no\n";
$id4 = uniqid("", true);
echo strlen($id4) > strlen($id1) ? "more-entropy\n" : "no\n";
