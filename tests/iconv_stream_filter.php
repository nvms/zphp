<?php
// the convert.iconv.* stream filter converts through iconv(3)
var_dump(in_array('convert.iconv.*', stream_get_filters()));
$file = tempnam(sys_get_temp_dir(), 'iconv');
file_put_contents($file, hex2bin('1b244224332473244b2441244f1b284269636f6e760a'));

foreach (['convert.iconv.ISO-2022-JP/EUC-JP', 'convert.iconv.ISO-2022-JP.EUC-JP', 'convert.iconv.ISO-2022-JP\0EUC-JP', 'convert.iconv.NOPE/UTF-8', 'convert.iconv.UTF-8'] as $name) {
    $fp = fopen($file, 'rb');
    var_dump(stream_filter_append($fp, $name) !== false);
    var_dump(bin2hex(fread($fp, 10)), bin2hex(fread($fp, 5)), bin2hex(fread($fp, 1)));
    fclose($fp);
}

// a filter before it breaks the encoding
$fp = fopen($file, 'rb');
stream_filter_append($fp, 'string.rot13');
stream_filter_append($fp, 'convert.iconv.ISO-2022-JP/EUC-JP');
var_dump(fread($fp, 10));
fclose($fp);

// php://filter and a chain through it
$url = "php://filter/read=" . urlencode("convert.iconv.ISO-8859-15/UTF-8") . '|' . urlencode("string.rot13")
    . '|' . urlencode("string.rot13") . '|' . urlencode("convert.iconv.UTF-8/ISO-8859-15") . "/resource=data://text/plain,foob%E2r";
var_dump(urlencode(file_get_contents($url)));
var_dump(bin2hex(file_get_contents("php://filter/read=convert.iconv.ISO-8859-1.UTF-16BE/resource=data://text/plain,h%E9")));

// a multibyte character split across writes waits for its last bytes
$fp = fopen($file, 'w');
stream_filter_append($fp, 'convert.iconv.UTF-8/ISO-8859-1');
fwrite($fp, "caf\xC3");
fwrite($fp, "\xA9 cr\xC3\xA8me");
fclose($fp);
var_dump(bin2hex(file_get_contents($file)));

// an incomplete character left at the end, and an invalid one
foreach (["ab\xC3", "ab\xFFcd"] as $bytes) {
    $fp = fopen($file, 'w');
    stream_filter_append($fp, 'convert.iconv.UTF-8/ISO-8859-1');
    var_dump(fwrite($fp, $bytes));
    var_dump(fclose($fp));
    var_dump(bin2hex(file_get_contents($file)));
}
$fp = fopen('php://memory', 'w+');
fwrite($fp, "x\xE2\x82\xACy");
rewind($fp);
stream_filter_append($fp, 'convert.iconv.UTF-8/ISO-8859-1', STREAM_FILTER_READ);
var_dump(stream_get_contents($fp));
fclose($fp);

// seeking resets the conversion, only to the start
$text = 'Hello, this is a test for iconv stream filter seeking functionality.';
file_put_contents($file, $text);
$fp = fopen($file, 'r');
stream_filter_append($fp, 'convert.iconv.UTF-8/ISO-2022-JP');
var_dump(fread($fp, 20));
var_dump(fseek($fp, 0, SEEK_SET));
var_dump(fread($fp, strlen($text)) === $text);
var_dump(fseek($fp, 50, SEEK_SET));
fclose($fp);

// a stateful encoding gets its shift sequence back at the close
$fp = fopen($file, 'w');
stream_filter_append($fp, 'convert.iconv.UTF-8/ISO-2022-JP');
fwrite($fp, "\xE3\x81\x82");
fclose($fp);
var_dump(bin2hex(file_get_contents($file)));

// growing output
var_dump(strlen(file_get_contents("php://filter/read=convert.iconv.UTF-8.UTF-32LE/resource=data://text/plain," . str_repeat('a', 5000))));
unlink($file);
