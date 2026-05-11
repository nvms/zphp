<?php
echo bin2hex(openssl_pbkdf2("password", "salt", 32, 1000, "sha256")), "\n";
echo bin2hex(openssl_pbkdf2("password", "salt", 16, 100, "sha1")), "\n";
echo bin2hex(openssl_pbkdf2("password", "salt", 64, 10000, "sha512")), "\n";
echo bin2hex(openssl_pbkdf2("", "", 16, 1, "sha256")), "\n";
echo bin2hex(openssl_pbkdf2("p", "s", 8, 1, "sha256")), "\n";
echo strlen(openssl_pbkdf2("password", "salt", 32, 1, "sha256")), "\n";
echo strlen(openssl_pbkdf2("password", "salt", 64, 1, "sha256")), "\n";

$pass = "my_password";
$salt = openssl_random_pseudo_bytes(16);
$key = openssl_pbkdf2($pass, $salt, 32, 10000, "sha256");
echo strlen($key), "\n";

$h1 = openssl_pbkdf2("abc", "salt", 32, 1000, "sha256");
$h2 = openssl_pbkdf2("abc", "salt", 32, 1000, "sha256");
echo ($h1 === $h2) ? "deterministic\n" : "non-det\n";

$h3 = openssl_pbkdf2("abc", "salt2", 32, 1000, "sha256");
echo ($h1 === $h3) ? "same\n" : "diff\n";

