<?php
// unpack() as php's pack.c reads formats: repeaters, names, the '*' and '@'
// codes, offsets, and its warnings and errors

$data = "\x01\x02\x03\x04\x05\x06\x07\x08foo \t\n\0bar\0baz";
$formats = [
    'C*', 'c2a/Cb', 'N2x/n', 'V', 'v*', 's3', 'Nfirst/Nsecond', 'C2name', 'C*1', 'C3x', 'X', 'X*', 'X2C',
    '@4C', '@100C', '@*C', 'x*C', 'H*', 'h3', 'H5', 'a*', 'A*', 'Z*', 'a5x/A4y/Z4z', 'Q', 'J', 'P', 'q',
    'g', 'G', 'e', 'E', 'f', 'd', 'C0', 'H0', 'a0', 'C2147483648', 'h2147483647', 'i', 'I', 'L', 'l',
    'Cx/C', 'C/C/C', '', 'C' . str_repeat('n', 250), 'Ckey/C2', 'C3' . '0', 'X3C', 'C9',
];
foreach ($formats as $f) {
    echo json_encode($f), ": ";
    try {
        var_dump(unpack($f, $data));
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
foreach ([0, 4, 25, 26, -1, 100] as $offset) {
    try {
        var_dump(unpack('C2', $data, $offset));
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
foreach (['B', 'Y2', 'u'] as $f) {
    try {
        unpack($f, $data);
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
var_dump(unpack('A*', "  a b \0 \r\n"), unpack('Z5', "ab"), unpack('a3', ""), unpack('H*', ""));
