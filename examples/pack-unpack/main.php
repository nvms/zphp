<?php
// covers: pack, unpack, bin2hex, strlen, implode, array_values

// --- integer packing: big-endian vs little-endian ---

$be = pack("N", 0x01020304);
$le = pack("V", 0x01020304);
echo "Big-endian 0x01020304: " . bin2hex($be) . "\n";
echo "Little-endian 0x01020304: " . bin2hex($le) . "\n";

// 16-bit
$be16 = pack("n", 0x0102);
$le16 = pack("v", 0x0102);
echo "Big-endian 16-bit 0x0102: " . bin2hex($be16) . "\n";
echo "Little-endian 16-bit 0x0102: " . bin2hex($le16) . "\n";

// 64-bit
$be64 = pack("J", 0x0102030405060708);
$le64 = pack("P", 0x0102030405060708);
echo "Big-endian 64-bit: " . bin2hex($be64) . "\n";
echo "Little-endian 64-bit: " . bin2hex($le64) . "\n";

// --- string packing ---

echo "\nString packing:\n";

// NUL-padded
$a = pack("a10", "Hello");
echo "a10 'Hello' length: " . strlen($a) . "\n";
echo "a10 'Hello' hex: " . bin2hex($a) . "\n";

// space-padded
$A = pack("A10", "Hello");
echo "A10 'Hello' hex: " . bin2hex($A) . "\n";

// Z (NUL-padded, strips on unpack)
$z = pack("Z10", "Hello");
echo "Z10 'Hello' hex: " . bin2hex($z) . "\n";

// star = exact length
$star = pack("a*", "Hello");
echo "a* 'Hello' length: " . strlen($star) . "\n";
echo "a* 'Hello' hex: " . bin2hex($star) . "\n";

// --- hex packing ---

echo "\nHex packing:\n";
$h = pack("H*", "48656c6c6f");
echo "H* '48656c6c6f': " . $h . "\n";
$h4 = pack("H4", "48656c6c6f");
echo "H4 '48656c6c6f': " . bin2hex($h4) . "\n";

// --- unsigned char packing ---

echo "\nChar packing:\n";
$chars = pack("C3", 65, 66, 67);
echo "C3 (65,66,67): " . $chars . "\n";
$chars2 = pack("C*", 72, 101, 108, 108, 111);
echo "C* (72,101,108,108,111): " . $chars2 . "\n";

// signed char
$sc = pack("c", -1);
echo "c(-1) hex: " . bin2hex($sc) . "\n";
$sc2 = pack("c", 127);
echo "c(127) hex: " . bin2hex($sc2) . "\n";

// --- unpack with named keys ---

echo "\nUnpack with named keys:\n";
$data = pack("Na5", 5, "Hello");
$result = unpack("Nlen/a5data", $data);
echo "len: " . $result['len'] . "\n";
echo "data: " . $result['data'] . "\n";

// --- round-trip: integers ---

echo "\nRound-trip integers:\n";
$packed = pack("NnVv", 123456, 789, 987654, 321);
$unpacked = unpack("Na/nb/Vc/vd", $packed);
echo "N: " . $unpacked['a'] . "\n";
echo "n: " . $unpacked['b'] . "\n";
echo "V: " . $unpacked['c'] . "\n";
echo "v: " . $unpacked['d'] . "\n";

// --- round-trip: 64-bit ---

echo "\nRound-trip 64-bit:\n";
$packed64 = pack("JP", 1000000000000, 2000000000000);
$unpacked64 = unpack("Jbig/Plittle", $packed64);
echo "J: " . $unpacked64['big'] . "\n";
echo "P: " . $unpacked64['little'] . "\n";

// --- float/double ---

echo "\nFloat/double packing:\n";
$f = pack("g", 3.14);
$uf = unpack("gval", $f);
echo "float round-trip ~3.14: ";
echo ($uf['val'] > 3.13 && $uf['val'] < 3.15) ? "ok" : "fail";
echo "\n";

$d = pack("e", 2.718281828);
$ud = unpack("eval", $d);
echo "double round-trip ~2.718: ";
echo ($ud['val'] > 2.718 && $ud['val'] < 2.719) ? "ok" : "fail";
echo "\n";

// big-endian float
$gf = pack("G", 1.5);
$ugf = unpack("Gval", $gf);
echo "big-endian float 1.5: " . $ugf['val'] . "\n";

// big-endian double
$gd = pack("E", 2.5);
$ugd = unpack("Eval", $gd);
echo "big-endian double 2.5: " . $ugd['val'] . "\n";

// --- NUL byte and positioning ---

echo "\nNUL and positioning:\n";
$x = pack("a3x2a3", "ABC", "DEF");
echo "a3x2a3 hex: " . bin2hex($x) . "\n";
echo "a3x2a3 length: " . strlen($x) . "\n";

// back up
$xb = pack("a5X2a2", "ABCDE", "XY");
echo "a5X2a2: " . $xb . "\n";

// absolute position
$at = pack("a3@10a3", "ABC", "DEF");
echo "@10 length: " . strlen($at) . "\n";
echo "@10 hex: " . bin2hex($at) . "\n";

// --- unpack with offset ---

echo "\nUnpack with offset:\n";
$data = pack("NNN", 100, 200, 300);
$r = unpack("Nval", $data, 4);
echo "offset 4: " . $r['val'] . "\n";
$r2 = unpack("Nval", $data, 8);
echo "offset 8: " . $r2['val'] . "\n";

// --- practical: DNS header parsing ---

echo "\nDNS header parse:\n";
$dns = pack("nnnnnn", 0x1234, 0x0100, 1, 0, 0, 0);
$header = unpack("nid/nflags/nqdcount/nancount/nnscount/narcount", $dns);
echo "ID: " . $header['id'] . "\n";
echo "Flags: " . $header['flags'] . "\n";
echo "Questions: " . $header['qdcount'] . "\n";

// --- practical: binary file header ---

echo "\nBinary file header:\n";
$magic = pack("a4NnCC", "ZPHP", 1, 0, 0x01, 0x00);
echo "Header hex: " . bin2hex($magic) . "\n";
echo "Header length: " . strlen($magic) . "\n";
$parsed = unpack("a4magic/Nversion/nflags/Ctype/Creserved", $magic);
echo "Magic: " . $parsed['magic'] . "\n";
echo "Version: " . $parsed['version'] . "\n";
echo "Type: " . $parsed['type'] . "\n";

// --- unpack A strips trailing spaces/NULs ---

echo "\nA unpack strips padding:\n";
$padded = pack("A10", "Hello");
$up = unpack("A10val", $padded);
echo "A10 unpacked: '" . $up['val'] . "'\n";

// --- unpack Z strips at first NUL ---

echo "\nZ unpack strips at NUL:\n";
$zp = pack("a10", "Hello");
$uz = unpack("Z10val", $zp);
echo "Z10 unpacked: '" . $uz['val'] . "'\n";

// --- multiple values same format ---

echo "\nMultiple C values:\n";
$multi = pack("C5", 10, 20, 30, 40, 50);
$um = unpack("C5", $multi);
echo implode(",", array_values($um)) . "\n";
