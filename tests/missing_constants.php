<?php

// previously-missing constants must all be defined
$required = [
    'PHP_OS_FAMILY', 'PHP_FLOAT_DIG',
    'PATHINFO_DIRNAME', 'PATHINFO_BASENAME', 'PATHINFO_EXTENSION', 'PATHINFO_FILENAME',
    'CRYPT_BLOWFISH', 'CRYPT_SHA256', 'CRYPT_SHA512',
    'PASSWORD_ARGON2I', 'PASSWORD_ARGON2ID',
    'OPENSSL_ALGO_SHA1', 'OPENSSL_ALGO_SHA256', 'OPENSSL_ALGO_SHA512',
    'OPENSSL_RAW_DATA', 'OPENSSL_ZERO_PADDING',
    'M_LOG2E', 'M_LOG10E', 'M_PI_2', 'M_PI_4',
    'M_1_PI', 'M_2_PI', 'M_SQRTPI', 'M_2_SQRTPI', 'M_SQRT1_2',
    'SIGTERM', 'SIGINT', 'SIGKILL',
    'AF_INET', 'AF_INET6', 'SOCK_STREAM', 'SOCK_DGRAM',
    'STREAM_CLIENT_CONNECT', 'STREAM_CLIENT_PERSISTENT',
    'DATE_ATOM', 'DATE_ISO8601', 'DATE_RFC2822', 'DATE_RFC3339', 'DATE_W3C',
];
foreach ($required as $c) {
    if (!defined($c)) echo "MISSING: $c\n";
}
echo "checked " . count($required) . " constants\n";

// PASSWORD_DEFAULT and PASSWORD_BCRYPT are strings, not ints, in PHP
echo gettype(PASSWORD_DEFAULT) . ":" . PASSWORD_DEFAULT . "\n";
echo gettype(PASSWORD_BCRYPT) . ":" . PASSWORD_BCRYPT . "\n";

// pathinfo constants form bitfield
echo (PATHINFO_DIRNAME | PATHINFO_BASENAME | PATHINFO_EXTENSION | PATHINFO_FILENAME) . "\n";

// math constants approximate
echo round(M_PI_2 * 2 - M_PI, 10) . "\n";
echo round(M_LN10 * M_LOG10E, 10) . "\n";

// sprintf NaN formatting
echo sprintf("%g", NAN) . "\n";
echo sprintf("%f", NAN) . "\n";
echo sprintf("%g", INF) . "\n";
echo sprintf("%g", -INF) . "\n";
echo sprintf("%f", 0.0) . "\n";
echo sprintf("%g", 0.0) . "\n";
