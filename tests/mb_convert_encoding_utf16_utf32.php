<?php
// regression: mb_convert_encoding handles UTF-16 (BE/LE), UTF-32 (BE/LE) round
// trips with UTF-8 and Latin1. surrogate pairs for codepoints outside BMP

// UTF-8 -> UTF-16BE
echo bin2hex(mb_convert_encoding("héllo", "UTF-16", "UTF-8")) . "\n";
echo bin2hex(mb_convert_encoding("héllo", "UTF-16BE", "UTF-8")) . "\n";
// UTF-8 -> UTF-16LE
echo bin2hex(mb_convert_encoding("héllo", "UTF-16LE", "UTF-8")) . "\n";

// surrogate pair (U+1F600 grinning face)
echo bin2hex(mb_convert_encoding("\u{1F600}", "UTF-16BE", "UTF-8")) . "\n";
echo bin2hex(mb_convert_encoding("\u{1F600}", "UTF-16LE", "UTF-8")) . "\n";

// round trip
$src = "héllo \u{1F600} 中文";
echo ($src === mb_convert_encoding(mb_convert_encoding($src, "UTF-16BE", "UTF-8"), "UTF-8", "UTF-16BE") ? 'y' : 'n') . "\n";
echo ($src === mb_convert_encoding(mb_convert_encoding($src, "UTF-16LE", "UTF-8"), "UTF-8", "UTF-16LE") ? 'y' : 'n') . "\n";
echo ($src === mb_convert_encoding(mb_convert_encoding($src, "UTF-32BE", "UTF-8"), "UTF-8", "UTF-32BE") ? 'y' : 'n') . "\n";
echo ($src === mb_convert_encoding(mb_convert_encoding($src, "UTF-32LE", "UTF-8"), "UTF-8", "UTF-32LE") ? 'y' : 'n') . "\n";

// UTF-32BE for codepoint above BMP
echo bin2hex(mb_convert_encoding("\u{1F600}", "UTF-32BE", "UTF-8")) . "\n";
echo bin2hex(mb_convert_encoding("\u{1F600}", "UTF-32LE", "UTF-8")) . "\n";

// Latin1 <-> UTF-16
echo bin2hex(mb_convert_encoding("\xe9", "UTF-16BE", "ISO-8859-1")) . "\n";   // é
echo bin2hex(mb_convert_encoding("\x00\xe9", "ISO-8859-1", "UTF-16BE")) . "\n";
