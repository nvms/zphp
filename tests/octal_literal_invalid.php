<?php
// an octal literal with an 8 or 9 in it is a parse error, as php's scanner
// reads it

$codes = [
    '$x = 08;',
    '$x = 0_9;',
    '$x = 019;',
    '$x = 0o8;',
    '$v = 017 + 0_17 + 0x1f + 0b11 + 0o7 + 00 + 08.5 + 09e1; echo $v, "\n";',
];
foreach ($codes as $code) {
    try {
        eval($code);
    } catch (ParseError $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
