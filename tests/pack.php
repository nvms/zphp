<?php
// unnamed format with repeat - sequential int keys
print_r(unpack("C3", "\x01\x02\x03"));
print_r(unpack("S2", "\x01\x00\x02\x00"));
print_r(unpack("N2", "\x00\x00\x00\x01\x00\x00\x00\x02"));

// named format with repeat - indexed suffix keys
print_r(unpack("C3flags", "\x01\x02\x03"));
print_r(unpack("C*bytes", "\x0a\x0b\x0c"));
print_r(unpack("S2words", "\x01\x00\x02\x00"));

// mixed named and unnamed
print_r(unpack("Cfirst/C2rest", "\x01\x02\x03"));
print_r(unpack("Cflag/C", "\x01\x02"));
print_r(unpack("Nhigh/nlow", pack("Nn", 0x12345678, 0xabcd)));

// unnamed counter collides per element
print_r(unpack("C/C", "\x01\x02"));
print_r(unpack("C2/C", "\x01\x02\x03"));
print_r(unpack("C/C2", "\x01\x02\x03"));
print_r(unpack("C2/C2", "\x01\x02\x03\x04"));

// signed vs unsigned
print_r(unpack("c", "\xff"));
print_r(unpack("C", "\xff"));
print_r(unpack("s", "\xff\xff"));
print_r(unpack("l", "\xff\xff\xff\xff"));
print_r(unpack("q", "\xff\xff\xff\xff\xff\xff\xff\xff"));

// endianness
print_r(unpack("n", "\x12\x34"));
print_r(unpack("v", "\x34\x12"));
print_r(unpack("N", "\x12\x34\x56\x78"));
print_r(unpack("V", "\x78\x56\x34\x12"));
print_r(unpack("J", "\x00\x00\x00\x00\x12\x34\x56\x78"));
print_r(unpack("P", "\x78\x56\x34\x12\x00\x00\x00\x00"));

// strings
print_r(unpack("a5", "hello"));
print_r(unpack("A5", "hi   "));
print_r(unpack("Z*", "world\x00trailing"));
print_r(unpack("Z10", "hi\x00\x00\x00\x00\x00\x00\x00\x00"));

// hex
print_r(unpack("H*", "\x12\x34"));
print_r(unpack("h*", "\x12\x34"));
print_r(unpack("H4", "\xab\xcd"));
print_r(unpack("H3", "\xab\xcd"));

// offset parameter
print_r(unpack("C2", "abcdef", 2));
print_r(unpack("Cfoo", "abcdef", 4));

// X (back up) and @ (absolute)
echo bin2hex(pack("NX3C", 0x11223344, 0xff)) . "\n";
echo bin2hex(pack("A10@3C", "hello", 99)) . "\n";

// Z NUL-padding rules (Zn reserves final byte for NUL, Z* appends NUL)
echo bin2hex(pack("Z5", "hi")) . "\n";
echo bin2hex(pack("Z5", "hello")) . "\n";
echo bin2hex(pack("Z5", "helloX")) . "\n";
echo bin2hex(pack("Z*", "hello")) . "\n";
echo bin2hex(pack("Z1", "abc")) . "\n";
echo bin2hex(pack("Z3", "")) . "\n";

// * for multiple values
echo bin2hex(pack("C*", 1, 2, 3, 4, 5)) . "\n";
echo bin2hex(pack("N*", 0x11111111, 0x22222222)) . "\n";

// H and h pack
echo bin2hex(pack("H*", "deadbeef")) . "\n";
echo bin2hex(pack("h*", "deadbeef")) . "\n";
echo bin2hex(pack("H3", "abc")) . "\n";

// pack negative and wrap
echo bin2hex(pack("s", -1)) . "\n";
echo bin2hex(pack("c", -128)) . "\n";
echo bin2hex(pack("C", 256)) . "\n";
echo bin2hex(pack("C", -1)) . "\n";

// floats
print_r(unpack("e", pack("e", 3.14)));
print_r(unpack("E", pack("E", 2.71)));
print_r(unpack("g", pack("g", 1.5)));
print_r(unpack("G", pack("G", 0.5)));

// roundtrip
$packed = pack("NnA5", 0xDEADBEEF, 0x1234, "hi");
print_r(unpack("Nmagic/nver/A5name", $packed));
