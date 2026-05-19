<?php
// regression: convert_uuencode / convert_uudecode round-trip arbitrary binary
// data. previously both raised 'Call to undefined function'. uuencode is
// legacy (mail attachments, .uu archives) but still appears in older PHP code
// and in cross-language interop pipelines. PHP's exact format: per line a
// length byte (0x20 + decoded_len, max 45) followed by 4-char groups encoding
// 3 bytes; trailing backtick line marks end of stream
$s = "Hello World!";
echo convert_uuencode($s);
echo convert_uudecode(convert_uuencode($s)) . "\n";

// round-trip arbitrary bytes including high-bit and \0
$bin = '';
for ($i = 0; $i < 256; $i++) $bin .= chr($i);
$bin = str_repeat($bin, 4);
var_dump($bin === convert_uudecode(convert_uuencode($bin)));

// multi-line input (>45 bytes triggers second line)
$long = str_repeat("ABCDEFGH", 12);
var_dump($long === convert_uudecode(convert_uuencode($long)));

// single short string
echo bin2hex(convert_uudecode(convert_uuencode("X"))) . "\n";

// uuencode output starts with comma (length 12 = chr(44) = ',')
echo convert_uuencode("Hello World!")[0] . "\n";
