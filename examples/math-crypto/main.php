<?php
// covers: abs, ceil, floor, round, max, min, pow, sqrt, log, fmod,
//   intdiv, number_format, base_convert, bindec, octdec, hexdec, decbin,
//   decoct, dechex, pi, M_PI, M_E, hash (md5, sha1, sha256), hash_hmac,
//   crc32, password_hash, password_verify, random_int, random_bytes,
//   is_numeric, intval, floatval, sprintf, array_sum, array_product

// --- basic math ---

echo "=== Basic Math ===\n";

echo "abs(-5): " . abs(-5) . "\n";
echo "abs(3.7): " . abs(3.7) . "\n";
echo "ceil(4.1): " . ceil(4.1) . "\n";
echo "ceil(-4.1): " . ceil(-4.1) . "\n";
echo "floor(4.9): " . floor(4.9) . "\n";
echo "floor(-4.9): " . floor(-4.9) . "\n";
echo "round(2.5): " . round(2.5) . "\n";
echo "round(2.55, 1): " . round(2.55, 1) . "\n";
echo "round(-1.5): " . round(-1.5) . "\n";

// --- min/max ---

echo "\n=== Min/Max ===\n";

echo "max(1,2,3): " . max(1, 2, 3) . "\n";
echo "min(1,2,3): " . min(1, 2, 3) . "\n";
echo "max(-5, 0, 5): " . max(-5, 0, 5) . "\n";
echo "min(-5, 0, 5): " . min(-5, 0, 5) . "\n";

// --- powers and roots ---

echo "\n=== Powers/Roots ===\n";

echo "pow(2, 10): " . pow(2, 10) . "\n";
echo "sqrt(144): " . sqrt(144) . "\n";
echo "sqrt(2): " . round(sqrt(2), 10) . "\n";
echo "log(M_E): " . round(log(M_E), 10) . "\n";
echo "log(100, 10): " . round(log(100, 10), 10) . "\n";

// --- integer division and modulo ---

echo "\n=== Division ===\n";

echo "intdiv(7, 2): " . intdiv(7, 2) . "\n";
echo "intdiv(-7, 2): " . intdiv(-7, 2) . "\n";
echo "fmod(10.5, 3.2): " . round(fmod(10.5, 3.2), 1) . "\n";
echo "fmod(-10.5, 3): " . fmod(-10.5, 3) . "\n";

// --- number formatting ---

echo "\n=== Number Format ===\n";

echo "number_format(1234567.891): " . number_format(1234567.891) . "\n";
echo "number_format(1234567.891, 2): " . number_format(1234567.891, 2) . "\n";
echo "number_format(1234567.891, 2, '.', ','): " . number_format(1234567.891, 2, '.', ',') . "\n";
echo "number_format(1234567.891, 2, ',', '.'): " . number_format(1234567.891, 2, ',', '.') . "\n";
echo "number_format(0.5, 0): " . number_format(0.5, 0) . "\n";
echo "number_format(1000, 0, '.', ''): " . number_format(1000, 0, '.', '') . "\n";

// --- base conversion ---

echo "\n=== Base Conversion ===\n";

echo "decbin(255): " . decbin(255) . "\n";
echo "bindec('11111111'): " . bindec('11111111') . "\n";
echo "decoct(255): " . decoct(255) . "\n";
echo "octdec('377'): " . octdec('377') . "\n";
echo "dechex(255): " . dechex(255) . "\n";
echo "hexdec('ff'): " . hexdec('ff') . "\n";
echo "base_convert('ff', 16, 2): " . base_convert('ff', 16, 2) . "\n";
echo "base_convert('11111111', 2, 16): " . base_convert('11111111', 2, 16) . "\n";

// --- constants ---

echo "\n=== Constants ===\n";

echo "M_PI: " . round(M_PI, 10) . "\n";
echo "M_E: " . round(M_E, 10) . "\n";
echo "PHP_INT_MAX: " . PHP_INT_MAX . "\n";
echo "PHP_INT_MIN: " . PHP_INT_MIN . "\n";
echo "PHP_FLOAT_MAX > 1e308: " . (PHP_FLOAT_MAX > 1e308 ? 'yes' : 'no') . "\n";

// --- hash functions ---

echo "\n=== Hash Functions ===\n";

echo "md5('hello'): " . md5('hello') . "\n";
echo "sha1('hello'): " . sha1('hello') . "\n";
echo "hash('sha256', 'hello'): " . hash('sha256', 'hello') . "\n";
echo "hash('md5', 'hello'): " . hash('md5', 'hello') . "\n";
echo "crc32('hello'): " . crc32('hello') . "\n";

// --- hmac ---

echo "\n=== HMAC ===\n";

echo "hash_hmac('sha256', 'data', 'key'): " . hash_hmac('sha256', 'data', 'key') . "\n";
echo "hash_hmac('md5', 'data', 'key'): " . hash_hmac('md5', 'data', 'key') . "\n";
echo "hash_hmac('sha1', 'data', 'key'): " . hash_hmac('sha1', 'data', 'key') . "\n";

// --- password hashing ---

echo "\n=== Password Hashing ===\n";

$hash = password_hash('secret123', PASSWORD_BCRYPT);
echo "hash starts with \$2: " . (str_starts_with($hash, '$2') ? 'yes' : 'no') . "\n";
echo "hash length: " . strlen($hash) . "\n";
echo "verify correct: " . (password_verify('secret123', $hash) ? 'yes' : 'no') . "\n";
echo "verify wrong: " . (password_verify('wrong', $hash) ? 'yes' : 'no') . "\n";

// --- random ---

echo "\n=== Random ===\n";

$r = random_int(1, 100);
echo "random_int in range: " . ($r >= 1 && $r <= 100 ? 'yes' : 'no') . "\n";
$bytes = random_bytes(16);
echo "random_bytes length: " . strlen($bytes) . "\n";
echo "random_bytes hex length: " . strlen(bin2hex($bytes)) . "\n";

// --- numeric checks ---

echo "\n=== Numeric Checks ===\n";

echo "is_numeric(42): " . (is_numeric(42) ? 'yes' : 'no') . "\n";
echo "is_numeric(3.14): " . (is_numeric(3.14) ? 'yes' : 'no') . "\n";
echo "is_numeric('42'): " . (is_numeric('42') ? 'yes' : 'no') . "\n";
echo "is_numeric('3.14'): " . (is_numeric('3.14') ? 'yes' : 'no') . "\n";
echo "is_numeric('0x1A'): " . (is_numeric('0x1A') ? 'yes' : 'no') . "\n";
echo "is_numeric('1e5'): " . (is_numeric('1e5') ? 'yes' : 'no') . "\n";
echo "is_numeric('abc'): " . (is_numeric('abc') ? 'yes' : 'no') . "\n";
echo "is_numeric(''): " . (is_numeric('') ? 'yes' : 'no') . "\n";
echo "is_numeric(true): " . (is_numeric(true) ? 'yes' : 'no') . "\n";
echo "is_numeric(null): " . (is_numeric(null) ? 'yes' : 'no') . "\n";

// --- type conversion ---

echo "\n=== Type Conversion ===\n";

echo "intval('42'): " . intval('42') . "\n";
echo "intval('0x1A', 16): " . intval('0x1A', 16) . "\n";
echo "intval('0b1010', 2): " . intval('0b1010', 2) . "\n";
echo "intval('077', 8): " . intval('077', 8) . "\n";
echo "floatval('3.14'): " . floatval('3.14') . "\n";
echo "floatval('1.2e3'): " . floatval('1.2e3') . "\n";

// --- sprintf with numbers ---

echo "\n=== Sprintf ===\n";

echo sprintf("decimal: %d", 42) . "\n";
echo sprintf("float: %.2f", 3.14159) . "\n";
echo sprintf("hex: %x", 255) . "\n";
echo sprintf("octal: %o", 255) . "\n";
echo sprintf("binary: %b", 255) . "\n";
echo sprintf("padded: %05d", 42) . "\n";
echo sprintf("string: %s", 'hello') . "\n";
echo sprintf("percent: %%") . "\n";
echo sprintf("multiple: %d + %d = %d", 2, 3, 5) . "\n";

// --- array math ---

echo "\n=== Array Math ===\n";

echo "array_sum([1,2,3,4,5]): " . array_sum([1, 2, 3, 4, 5]) . "\n";
echo "array_product([1,2,3,4,5]): " . array_product([1, 2, 3, 4, 5]) . "\n";
echo "array_sum([]): " . array_sum([]) . "\n";
echo "array_product([]): " . array_product([]) . "\n";
echo "array_sum([1.5, 2.5, 3.0]): " . array_sum([1.5, 2.5, 3.0]) . "\n";

echo "\nDone.\n";
