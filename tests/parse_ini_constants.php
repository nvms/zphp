<?php
// regression: parse_ini_string in NORMAL and TYPED scanner modes
// substitutes defined constants (both built-in PHP_INT_MAX/PHP_EOL and
// user-defined via define()). previously zphp left the constant name as
// a literal string. RAW mode still passes through unchanged
define('MYCONST', 42);

// NORMAL mode (default): bare identifier substituted, value coerced to string
print_r(parse_ini_string("k=MYCONST"));
print_r(parse_ini_string("k=PHP_INT_MAX"));

// TYPED mode: substituted with the constant's native type
print_r(parse_ini_string("k=MYCONST", false, INI_SCANNER_TYPED));
print_r(parse_ini_string("k=PHP_INT_MAX", false, INI_SCANNER_TYPED));

// RAW mode: constant names left as literal strings
print_r(parse_ini_string("k=MYCONST", false, INI_SCANNER_RAW));
print_r(parse_ini_string("k=PHP_INT_MAX", false, INI_SCANNER_RAW));

// non-identifier values aren't substituted
print_r(parse_ini_string("k=hello world"));
print_r(parse_ini_string("k=42"));

// unknown identifier left as-is
print_r(parse_ini_string("k=NOT_A_CONST"));
