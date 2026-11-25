<?php

// pack_endian_modifiers
var_dump(bin2hex(pack("s<", 0x0102)));
var_dump(bin2hex(pack("S<", 0x0102)));

var_dump(bin2hex(pack("s>", 0x0102)));
var_dump(bin2hex(pack("S>", 0x0102)));

var_dump(pack("s<", 0x0102) === pack("v", 0x0102));
var_dump(pack("S<", 0x0102) === pack("v", 0x0102));

var_dump(pack("s>", 0x0102) === pack("n", 0x0102));
var_dump(pack("S>", 0x0102) === pack("n", 0x0102));

var_dump(bin2hex(pack("l<", 0x01020304)));
var_dump(bin2hex(pack("L<", 0x01020304)));

var_dump(bin2hex(pack("l>", 0x01020304)));
var_dump(bin2hex(pack("L>", 0x01020304)));

var_dump(pack("l<", 0x01020304) === pack("V", 0x01020304));
var_dump(pack("L<", 0x01020304) === pack("V", 0x01020304));

var_dump(pack("l>", 0x01020304) === pack("N", 0x01020304));
var_dump(pack("L>", 0x01020304) === pack("N", 0x01020304));

// === Integer unpack with endianness modifiers ===

var_dump(unpack("s<", "\x02\x01"));
var_dump(unpack("S<", "\x02\x01"));

var_dump(unpack("s>", "\x01\x02"));
var_dump(unpack("S>", "\x01\x02"));

var_dump(unpack("s<", "\xfe\xff"));  // -2 in little-endian
var_dump(unpack("s>", "\xff\xfe"));  // -2 in big-endian

var_dump(unpack("l<", "\x04\x03\x02\x01"));
var_dump(unpack("L<", "\x04\x03\x02\x01"));

var_dump(unpack("l>", "\x01\x02\x03\x04"));
var_dump(unpack("L>", "\x01\x02\x03\x04"));

var_dump(unpack("l<", "\xfe\xff\xff\xff"));  // -2 in little-endian
var_dump(unpack("l>", "\xff\xff\xff\xfe"));  // -2 in big-endian

var_dump(bin2hex(pack("s<2", 0x0102, 0x0304)));
var_dump(bin2hex(pack("s>2", 0x0102, 0x0304)));

var_dump(unpack("s<2", "\x02\x01\x04\x03"));
var_dump(unpack("s>2", "\x01\x02\x03\x04"));

var_dump(unpack("s<value/L>count", "\x02\x01\x00\x00\x00\x05"));

var_dump(pack("f<", 3.14) === pack("g", 3.14));
var_dump(pack("f>", 3.14) === pack("G", 3.14));

var_dump(pack("d<", 3.14) === pack("e", 3.14));
var_dump(pack("d>", 3.14) === pack("E", 3.14));

$packed_le = pack("g", 3.14);
$packed_be = pack("G", 3.14);
$unpacked_le = unpack("f<", $packed_le);
$unpacked_be = unpack("f>", $packed_be);
$unpacked_g = unpack("g", $packed_le);
$unpacked_G = unpack("G", $packed_be);
var_dump($unpacked_le[1] === $unpacked_g[1]);
var_dump($unpacked_be[1] === $unpacked_G[1]);

$packed_le = pack("e", 3.14);
$packed_be = pack("E", 3.14);
$unpacked_le = unpack("d<", $packed_le);
$unpacked_be = unpack("d>", $packed_be);
$unpacked_e = unpack("e", $packed_le);
$unpacked_E = unpack("E", $packed_be);
var_dump($unpacked_le[1] === $unpacked_e[1]);
var_dump($unpacked_be[1] === $unpacked_E[1]);

$machine_float = pack("f", 1.5);
var_dump(unpack("f", $machine_float)[1] === 1.5);

$machine_double = pack("d", 1.5);
var_dump(unpack("d", $machine_double)[1] === 1.5);

// pack_endian_modifiers_64
var_dump(bin2hex(pack("q<", 0x0102030405060708)));
var_dump(bin2hex(pack("Q<", 0x0102030405060708)));

var_dump(bin2hex(pack("q>", 0x0102030405060708)));
var_dump(bin2hex(pack("Q>", 0x0102030405060708)));

var_dump(pack("q<", 0x0102030405060708) === pack("P", 0x0102030405060708));
var_dump(pack("Q<", 0x0102030405060708) === pack("P", 0x0102030405060708));

var_dump(pack("q>", 0x0102030405060708) === pack("J", 0x0102030405060708));
var_dump(pack("Q>", 0x0102030405060708) === pack("J", 0x0102030405060708));

var_dump(unpack("q<", "\x08\x07\x06\x05\x04\x03\x02\x01"));
var_dump(unpack("Q<", "\x08\x07\x06\x05\x04\x03\x02\x01"));

var_dump(unpack("q>", "\x01\x02\x03\x04\x05\x06\x07\x08"));
var_dump(unpack("Q>", "\x01\x02\x03\x04\x05\x06\x07\x08"));

var_dump(unpack("q<", "\xfe\xff\xff\xff\xff\xff\xff\xff"));  // -2 in little-endian
var_dump(unpack("q>", "\xff\xff\xff\xff\xff\xff\xff\xfe"));  // -2 in big-endian

// pack_endian_modifiers_error
$inherent_formats = ['n<', 'v>', 'N<', 'V>', 'J<', 'P>'];
foreach ($inherent_formats as $fmt) {
    try {
        pack($fmt, 1);
        echo "FAIL: Expected ValueError for pack('$fmt', 1)\n";
    } catch (ValueError $e) {
        echo "pack('$fmt'): " . $e->getMessage() . "\n";
    }
}

$inherent_float_formats = ['g<', 'G>', 'e<', 'E>'];
foreach ($inherent_float_formats as $fmt) {
    try {
        pack($fmt, 1.0);
        echo "FAIL: Expected ValueError for pack('$fmt', 1.0)\n";
    } catch (ValueError $e) {
        echo "pack('$fmt'): " . $e->getMessage() . "\n";
    }
}

$unsupported_formats = ['c<', 'C>', 'a<', 'A>', 'h<', 'H>', 'i<', 'I>', 'x<', 'X>', '@<'];
foreach ($unsupported_formats as $fmt) {
    try {
        pack($fmt, 1);
        echo "FAIL: Expected ValueError for pack('$fmt', 1)\n";
    } catch (ValueError $e) {
        echo "pack('$fmt'): " . $e->getMessage() . "\n";
    }
}

foreach (['n<', 'v>', 'N<', 'V>', 'J<', 'P>'] as $fmt) {
    try {
        unpack($fmt, "\x00\x00\x00\x00\x00\x00\x00\x00");
        echo "FAIL: Expected ValueError for unpack('$fmt', ...)\n";
    } catch (ValueError $e) {
        echo "unpack('$fmt'): " . $e->getMessage() . "\n";
    }
}

foreach (['g<', 'G>', 'e<', 'E>'] as $fmt) {
    try {
        unpack($fmt, "\x00\x00\x00\x00\x00\x00\x00\x00");
        echo "FAIL: Expected ValueError for unpack('$fmt', ...)\n";
    } catch (ValueError $e) {
        echo "unpack('$fmt'): " . $e->getMessage() . "\n";
    }
}

foreach (['c<', 'C>', 'a<', 'A>', 'h<', 'H>', 'i<', 'I>', 'x<', 'X>', '@<'] as $fmt) {
    try {
        unpack($fmt, "\x00\x00\x00\x00\x00\x00\x00\x00");
        echo "FAIL: Expected ValueError for unpack('$fmt', ...)\n";
    } catch (ValueError $e) {
        echo "unpack('$fmt'): " . $e->getMessage() . "\n";
    }
}

// unpack_endian_modifier_names
var_dump(unpack("s<value", "\x02\x01"));
var_dump(unpack("s>value", "\x01\x02"));

var_dump(unpack("s<2name", "\x02\x01\x04\x03"));
var_dump(unpack("s<*name", "\x02\x01\x04\x03"));

var_dump(unpack("v1<value", "\x02\x01"));
var_dump(unpack("n2>name", "\x01\x02\x03\x04"));
var_dump(unpack("C1>name", "\x01"));

// unpack_endian_modifier_names_error
foreach (["C>name", "@>name", "n<name", "V>name"] as $fmt) {
    try {
        unpack($fmt, "\x01\x02\x03\x04\x05\x06\x07\x08");
        echo "FAIL: Expected ValueError for unpack('$fmt', ...)\n";
    } catch (ValueError $e) {
        echo "unpack('$fmt'): " . $e->getMessage() . "\n";
    }
}

// codes zphp's own probes add
foreach (['Y<', '*>', 'Z<', 'Z>', 'q>', 's>*'] as $fmt) {
    try {
        var_dump(bin2hex(pack($fmt, -3, 7)));
    } catch (ValueError $e) {
        echo "pack('$fmt'): " . $e->getMessage() . "\n";
    }
    try {
        var_dump(unpack($fmt, "\xff\xfe\xfd\xfc\xfb\xfa\xf9\xf8"));
    } catch (ValueError $e) {
        echo "unpack('$fmt'): " . $e->getMessage() . "\n";
    }
}
var_dump(bin2hex(pack("s>S<l>L<q>Q<f>d<", -2, 2, -3, 3, -4, 4, 1.5, 2.5)));
var_dump(unpack("s>a/S<b/l>c/L<d/q>e/Q<f/f>g/d<h", pack("s>S<l>L<q>Q<f>d<", -2, 2, -3, 3, -4, 4, 1.5, 2.5)));
