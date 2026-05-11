<?php
$data = "hello world";
$c = gzcompress($data);
echo strlen($c) > 0 ? "y" : "n", "\n";
$u = gzuncompress($c);
echo $u === $data ? "y" : "n", "\n";

$big = str_repeat("hello world ", 100);
$c = gzcompress($big);
echo strlen($c) < strlen($big) ? "y" : "n", "\n";
$u = gzuncompress($c);
echo $u === $big ? "y" : "n", "\n";

$c1 = gzcompress("test", 1);
$c2 = gzcompress("test", 9);
echo strlen($c1) > 0 && strlen($c2) > 0 ? "y" : "n", "\n";
echo gzuncompress($c1) === "test" ? "y" : "n", "\n";
echo gzuncompress($c2) === "test" ? "y" : "n", "\n";

$data = "hello world";
$d = gzdeflate($data);
echo strlen($d) > 0 ? "y" : "n", "\n";
$i = gzinflate($d);
echo $i === $data ? "y" : "n", "\n";

$encoded = gzencode("hello");
echo strlen($encoded) > 0 ? "y" : "n", "\n";
echo substr($encoded, 0, 2) === "\x1f\x8b" ? "y" : "n", "\n";
echo gzdecode($encoded) === "hello" ? "y" : "n", "\n";

$multiline = "line1\nline2\nline3\n";
$c = gzcompress($multiline);
$u = gzuncompress($c);
echo $u === $multiline ? "y" : "n", "\n";

$binary = "\x00\x01\x02\x03\xff\xfe\xfd";
$c = gzcompress($binary);
$u = gzuncompress($c);
echo $u === $binary ? "y" : "n", "\n";

$empty = "";
$c = gzcompress($empty);
echo gzuncompress($c) === "" ? "y" : "n", "\n";

$test = "compressible compressible compressible";
$c = gzcompress($test, 6);
$ec = gzencode($test, 6);
$df = gzdeflate($test, 6);

echo strlen($c) > 0 && strlen($ec) > 0 && strlen($df) > 0 ? "y" : "n", "\n";

echo gzuncompress($c) === $test ? "y" : "n", "\n";
echo gzdecode($ec) === $test ? "y" : "n", "\n";
echo gzinflate($df) === $test ? "y" : "n", "\n";

$bad = "not really compressed";
echo @gzuncompress($bad) === false ? "y" : "n", "\n";
echo @gzdecode($bad) === false ? "y" : "n", "\n";
echo @gzinflate($bad) === false ? "y" : "n", "\n";

$pattern = str_repeat("ABC", 1000);
$c = gzcompress($pattern);
echo strlen($c) < strlen($pattern) / 10 ? "y" : "n", "\n";
echo gzuncompress($c) === $pattern ? "y" : "n", "\n";

$utf = "héllo 日本語 world";
$c = gzcompress($utf);
$u = gzuncompress($c);
echo $u === $utf ? "y" : "n", "\n";

$strategies = [
    0 => "no",
    1 => "best-speed",
    6 => "default",
    9 => "best-comp",
];
foreach ([1, 5, 9] as $level) {
    $c = gzcompress("test data $level", $level);
    echo gzuncompress($c), "\n";
}

echo function_exists("gzcompress") ? "y" : "n", "\n";
echo function_exists("gzuncompress") ? "y" : "n", "\n";
echo function_exists("gzdeflate") ? "y" : "n", "\n";
echo function_exists("gzinflate") ? "y" : "n", "\n";
echo function_exists("gzencode") ? "y" : "n", "\n";
echo function_exists("gzdecode") ? "y" : "n", "\n";
