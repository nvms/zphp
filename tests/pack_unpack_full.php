<?php
echo bin2hex(pack("a", "A")), "\n";
echo bin2hex(pack("a4", "AB")), "\n";
echo bin2hex(pack("A4", "AB")), "\n";
echo bin2hex(pack("a*", "hello")), "\n";

echo bin2hex(pack("c", 65)), "\n";
echo bin2hex(pack("C", 255)), "\n";
echo bin2hex(pack("c2", 1, 2)), "\n";

echo bin2hex(pack("n", 1234)), "\n";
echo bin2hex(pack("v", 1234)), "\n";
echo bin2hex(pack("N", 1234567890)), "\n";
echo bin2hex(pack("V", 1234567890)), "\n";

echo bin2hex(pack("q", 0x0102030405060708)), "\n";
echo bin2hex(pack("Q", 0x0102030405060708)), "\n";
echo bin2hex(pack("J", 0x0102030405060708)), "\n";
echo bin2hex(pack("P", 0x0102030405060708)), "\n";

echo bin2hex(pack("f", 1.5)), "\n";
echo bin2hex(pack("d", 1.5)), "\n";

echo bin2hex(pack("Z4", "AB")), "\n";

echo bin2hex(pack("x")), "\n";
echo bin2hex(pack("x4")), "\n";

echo bin2hex(pack("a3X1a2", "abc", "DE")), "\n";

echo bin2hex(pack("a3@5a2", "abc", "DE")), "\n";

echo bin2hex(pack("nNc", 1234, 5678, 99)), "\n";

echo bin2hex(pack("c*", 1, 2, 3, 4, 5)), "\n";

print_r(unpack("c", "\x41"));
print_r(unpack("C", "\xff"));
print_r(unpack("n", "\x04\xd2"));
print_r(unpack("v", "\xd2\x04"));
print_r(unpack("N", pack("N", 1234567890)));
print_r(unpack("V", pack("V", 1234567890)));
print_r(unpack("q", pack("q", 0x0102030405060708)));
print_r(unpack("J", pack("J", 0x0102030405060708)));
print_r(unpack("P", pack("P", 0x0102030405060708)));

print_r(unpack("c2", "\x01\x02"));
print_r(unpack("c2first/c2second", "\x01\x02\x03\x04"));
print_r(unpack("nx/Cy", pack("n", 1234) . "\x42"));

print_r(unpack("a4", "AB\x00\x00"));
print_r(unpack("A4", "AB  "));
print_r(unpack("Z4", "AB\x00\x00"));

print_r(unpack("a3val/x/c1after", "abc\x00\x42"));

print_r(unpack("c*", "\x01\x02\x03\x04\x05"));

print_r(unpack("nfirst/Csecond/A2third", "\x04\xd2\x42AB"));

print_r(unpack("f", pack("f", 1.5)));
print_r(unpack("d", pack("d", 1.5)));

$bin = pack("nNa4", 1, 2, "test");
print_r(unpack("nver/Nlen/a4tag", $bin));

$header = pack("VVa4", 0xDEADBEEF, 100, "TYPE");
$data = unpack("Vmagic/Vsize/a4type", $header);
echo dechex($data["magic"]), "/", $data["size"], "/", $data["type"], "\n";

echo bin2hex(pack("c1", 0)), "\n";
echo bin2hex(pack("c", -1)), "\n";

print_r(unpack("c", "\xff"));

echo bin2hex(pack("v", 0)), "\n";
echo bin2hex(pack("V", 0)), "\n";

echo bin2hex(pack("n3", 1, 2, 3)), "\n";
print_r(unpack("n3", "\x00\x01\x00\x02\x00\x03"));

echo bin2hex(pack("nN", 0xFFFF, 0xFFFFFFFF)), "\n";

echo bin2hex(pack("ZZ", "A", "B")), "\n";

echo strlen(pack("Z10", "hi")), "\n";

print_r(unpack("Z10", str_repeat("\x00", 10)));
