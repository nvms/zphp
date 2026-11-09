<?php
// %u, %o, %x, %X, %b and %c read the integer as unsigned 64 bits

$values = [0, 1, 7, 8, 255, 256, 4095, 65535, -1, -2, -255, -256, PHP_INT_MAX, PHP_INT_MIN, PHP_INT_MIN + 1, 2147483647, -2147483648, 4294967296];
foreach ($values as $v) {
    printf("%21d %20u %22o %16x %16X %64b\n", $v, $v, $v, $v, $v, $v);
}

// file permissions, colours and flags the way real code prints them
printf("mode %o, %04o, %'010o\n", 0755, 0644, 01777);
foreach ([[255, 136, 0], [18, 52, 86], [0, 0, 0]] as [$r, $g, $b]) {
    printf("#%02x%02x%02x #%02X%02X%02X\n", $r, $g, $b, $r, $g, $b);
}
printf("flags %08b %'.16b %-8b|\n", 0b1011, 0xF0F, 5);
printf("crc32 %08x %u\n", crc32('The quick brown fox'), crc32('The quick brown fox'));
printf("addr 0x%016x\n", 140737488355327);

// width pads, a zero flag pads with zeros, a minus flag pads on the right
printf("[%10x][%-10x][%010x][%'#10x][%-'#10x]\n", 48879, 48879, 48879, 48879, 48879);
printf("[%5u][%-5u][%05u][%-05u][%+u][%+d]\n", 42, 42, 42, 42, 42, 42);

// %c writes one byte: the low 8 bits, ignoring width and flags
printf("[%c%c%c][%5c][%-5c][%c][%c]\n", 80, 72, 80, 65, 66, 256 + 67, -191);
var_dump(bin2hex(sprintf('%c%c%c', 0, 255, 128)));

// non-integers convert first
printf("%x %o %b %u\n", 255.9, '255', true, -0.5);
printf("%x %u\n", '0xFF', ' 18446744073709551615');
printf("%X %b\n", 1.8446744073709552e19, -1.5e19);

// numbers through the other specifiers
foreach ([1, -1, 1234567, -1234567, PHP_INT_MAX] as $n) {
    printf("%d|%+d|%e|%.3e|%g|%G|%s|%f\n", $n, $n, $n, $n, $n, $n, $n, $n);
}
