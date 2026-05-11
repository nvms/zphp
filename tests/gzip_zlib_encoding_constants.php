<?php
$data = str_repeat("Hello, World! ", 100);

$enc = gzencode($data);
echo strlen($enc) < strlen($data) ? "y" : "n", "\n";
echo gzdecode($enc) === $data ? "y" : "n", "\n";

$compressed = gzcompress($data);
echo gzuncompress($compressed) === $data ? "y" : "n", "\n";

$deflated = gzdeflate($data);
echo gzinflate($deflated) === $data ? "y" : "n", "\n";

echo strlen(gzencode($data, 1)) >= strlen(gzencode($data, 9)) ? "y" : "n", "\n";
echo gzdecode(gzencode("")) === "" ? "y" : "n", "\n";

$binary = "";
for ($i = 0; $i < 256; $i++) $binary .= chr($i);
echo gzdecode(gzencode($binary)) === $binary ? "y" : "n", "\n";

$multiline = "line1\nline2\nline3\n";
echo strlen(gzdecode(gzencode($multiline))), "\n";

echo bin2hex(gzcompress("hello", 6)), "\n";
echo bin2hex(gzdeflate("hi")), "\n";

echo function_exists("gzencode") ? "y" : "n", "\n";
echo function_exists("gzdecode") ? "y" : "n", "\n";
echo function_exists("gzcompress") ? "y" : "n", "\n";
echo function_exists("gzuncompress") ? "y" : "n", "\n";
echo function_exists("gzdeflate") ? "y" : "n", "\n";
echo function_exists("gzinflate") ? "y" : "n", "\n";

echo defined("ZLIB_ENCODING_RAW") ? "y" : "n", "\n";
echo defined("ZLIB_ENCODING_GZIP") ? "y" : "n", "\n";
echo defined("ZLIB_ENCODING_DEFLATE") ? "y" : "n", "\n";

$tmp = tempnam(sys_get_temp_dir(), "gz_");
file_put_contents("compress.zlib://$tmp", "stream content via wrapper");
echo file_get_contents("compress.zlib://$tmp"), "\n";
unlink($tmp);

$big = str_repeat("data ", 1000);
echo strlen(gzencode($big)) < strlen($big) ? "y" : "n", "\n";
echo gzdecode(gzencode($big)) === $big ? "y" : "n", "\n";

echo bin2hex(substr(gzencode("test"), 0, 2)), "\n";
