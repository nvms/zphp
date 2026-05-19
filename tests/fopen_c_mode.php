<?php
// regression: fopen mode 'c' and 'c+' open for writing without truncating
// (creating if missing). previously zphp returned 'Failed to open stream:
// Unknown error' because the mode wasn't recognized
$tmp = "/tmp/zphp_fopen_c_test.txt";
@unlink($tmp);

// 'c' on missing file: creates it
$f = fopen($tmp, "c");
fwrite($f, "hello");
fclose($f);
echo file_get_contents($tmp) . "\n";   // "hello"

// 'c' on existing file: opens at position 0, no truncate
$f = fopen($tmp, "c");
fwrite($f, "Y");
fclose($f);
echo file_get_contents($tmp) . "\n";   // "Yello" (overwrote first byte)

// 'c+' allows reading + writing without truncating
$f = fopen($tmp, "c+");
echo fread($f, 5) . "\n";   // "Yello"
fseek($f, 0);
fwrite($f, "Z");
rewind($f);
echo fread($f, 5) . "\n";   // "Zello"
fclose($f);

unlink($tmp);
