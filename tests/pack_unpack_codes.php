<?php
echo bin2hex(pack("N", 0x01020304)), "\n";
echo bin2hex(pack("V", 0x01020304)), "\n";
echo bin2hex(pack("n", 0x0102)), "\n";
echo bin2hex(pack("v", 0x0102)), "\n";
echo bin2hex(pack("C", 0xff)), "\n";
echo bin2hex(pack("c", 0x12)), "\n";
echo bin2hex(pack("s", 0x0102)), "\n";
echo bin2hex(pack("S", 0xfedc)), "\n";
echo bin2hex(pack("l", 0x01020304)), "\n";
echo bin2hex(pack("L", 0xfedcba98)), "\n";
echo bin2hex(pack("J", 0x0102030405060708)), "\n";
echo bin2hex(pack("P", 0x0102030405060708)), "\n";

echo bin2hex(pack("a5", "hi")), "\n";
echo bin2hex(pack("A5", "hi")), "\n";
echo bin2hex(pack("Z5", "hi")), "\n";
echo bin2hex(pack("a5", "abcdefg")), "\n";
echo bin2hex(pack("xCx", 0x42)), "\n";

echo bin2hex(pack("N3", 1, 2, 3)), "\n";
echo bin2hex(pack("C*", 1, 2, 3, 4, 5)), "\n";
echo bin2hex(pack("n*", 1, 2, 3)), "\n";

print_r(unpack("N", "\x01\x02\x03\x04"));
print_r(unpack("V", "\x01\x02\x03\x04"));
print_r(unpack("n", "\x01\x02"));
print_r(unpack("v", "\x01\x02"));
print_r(unpack("c", "\xff"));
print_r(unpack("C", "\xff"));

print_r(unpack("Na/Nb", "\x00\x00\x00\x01\x00\x00\x00\x02"));
print_r(unpack("N2", "\x00\x00\x00\x01\x00\x00\x00\x02"));
print_r(unpack("N*", "\x00\x00\x00\x01\x00\x00\x00\x02\x00\x00\x00\x03"));
print_r(unpack("Na/n2b/C*c", "\x00\x00\x00\x01\x00\x02\x00\x03\xaa\xbb"));

print_r(unpack("a5str", "hello"));
print_r(unpack("A5str", "hello"));
print_r(unpack("Z5str", "hi\x00\x00\x00"));
print_r(unpack("A5str", "hi   "));

print_r(unpack("N", "\xff\xff\xff\xff"));
print_r(unpack("V", "\xff\xff\xff\xff"));
print_r(unpack("l", pack("l", -1)));
print_r(unpack("L", pack("L", 4294967295)));

print_r(unpack("@0/N1a/@4/N1b", "\x00\x00\x00\x01\x00\x00\x00\x02"));
print_r(unpack("@4/Nb", "\x00\x00\x00\x01\x00\x00\x00\x02"));

print_r(unpack("J", "\x01\x02\x03\x04\x05\x06\x07\x08"));
print_r(unpack("P", "\x01\x02\x03\x04\x05\x06\x07\x08"));

$packed = pack("NnC", 0xDEADBEEF, 0xCAFE, 0x42);
echo bin2hex($packed), "\n";
print_r(unpack("Nmagic/nver/Cflag", $packed));

$bin = pack("Na10n", 0x12345678, "metadata", 99);
echo bin2hex($bin), "\n";
print_r(unpack("Nhdr/a10name/nport", $bin));
