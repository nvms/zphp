<?php
echo bin2hex(pack("c", 1)), "\n";
echo bin2hex(pack("c", -1)), "\n";
echo bin2hex(pack("c", 127)), "\n";
echo bin2hex(pack("C", 255)), "\n";
echo bin2hex(pack("C", 1)), "\n";

echo bin2hex(pack("n", 0x1234)), "\n";
echo bin2hex(pack("n", 1)), "\n";
echo bin2hex(pack("n", 0xffff)), "\n";

echo bin2hex(pack("v", 0x1234)), "\n";
echo bin2hex(pack("v", 1)), "\n";
echo bin2hex(pack("v", 0xffff)), "\n";

echo bin2hex(pack("N", 0x12345678)), "\n";
echo bin2hex(pack("N", 1)), "\n";

echo bin2hex(pack("V", 0x12345678)), "\n";
echo bin2hex(pack("V", 1)), "\n";

echo bin2hex(pack("Q", 0x123456789abcdef0)), "\n";
echo bin2hex(pack("Q", 1)), "\n";

echo bin2hex(pack("q", 1)), "\n";
echo bin2hex(pack("q", -1)), "\n";

echo bin2hex(pack("a5", "hi")), "\n";
echo bin2hex(pack("a5", "hello")), "\n";
echo bin2hex(pack("a5", "longstring")), "\n";

echo bin2hex(pack("A5", "hi")), "\n";
echo bin2hex(pack("A5", "hello")), "\n";

echo bin2hex(pack("Z5", "hi")), "\n";
echo bin2hex(pack("Z5", "hello")), "\n";

echo bin2hex(pack("x")), "\n";
echo bin2hex(pack("xxx")), "\n";
echo bin2hex(pack("x4")), "\n";

echo bin2hex(pack("ncn", 1, 2, 3)), "\n";
echo bin2hex(pack("a3n", "abc", 5)), "\n";

print_r(unpack("c", "\x01"));
print_r(unpack("c", "\xff"));
print_r(unpack("C", "\xff"));

print_r(unpack("n", "\x12\x34"));
print_r(unpack("v", "\x12\x34"));
print_r(unpack("N", "\x12\x34\x56\x78"));
print_r(unpack("V", "\x12\x34\x56\x78"));

print_r(unpack("a5", "hello"));
print_r(unpack("a5", "hi\0\0\0"));
print_r(unpack("A5", "hi   "));
print_r(unpack("A5", "hello"));
print_r(unpack("Z5", "hi\0\0\0"));

print_r(unpack("cfirst/csecond", "\x01\x02"));
print_r(unpack("nbig/nother", "\x00\x01\x00\x02"));
print_r(unpack("a3str/nnum", "abc\x00\x05"));

print_r(unpack("c*", "\x01\x02\x03\x04"));
print_r(unpack("n*", "\x00\x01\x00\x02"));

$d = pack("d", 3.14);
$r = unpack("d", $d);
echo abs($r[1] - 3.14) < 1e-10 ? "y" : "n", "\n";

$d = pack("f", 1.5);
$r = unpack("f", $d);
echo abs($r[1] - 1.5) < 1e-5 ? "y" : "n", "\n";

$payload = pack("Nn", 100, 200);
$out = unpack("Nfirst/nsecond", $payload);
echo $out["first"], " ", $out["second"], "\n";

$rec = pack("a16NN", "header", 1000, 2000);
$dec = unpack("a16name/Nval1/Nval2", $rec);
echo trim($dec["name"]), " ", $dec["val1"], " ", $dec["val2"], "\n";

$signed = pack("c", -128);
$r = unpack("c", $signed);
echo $r[1], "\n";

$small = pack("vvv", 1, 256, 65535);
$r = unpack("v3", $small);
print_r($r);

echo bin2hex(pack("cn", 0xff, 0x1234)), "\n";

echo strlen(pack("a100", "x")), "\n";
echo strlen(pack("A100", "x")), "\n";

$mixed = pack("NnC", 1, 2, 3);
echo strlen($mixed), " ", bin2hex($mixed), "\n";
$out = unpack("Na/nb/Cc", $mixed);
print_r($out);
