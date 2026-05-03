<?php

// password_hash uses PHP's $2y$ prefix and default cost 12
$h = password_hash('mypass', PASSWORD_BCRYPT);
echo strlen($h) . "\n";
echo substr($h, 0, 7) . "\n";

// round-trip verify
echo password_verify('mypass', $h) ? "yes" : "no";
echo "\n";
echo password_verify('wrong', $h) ? "yes" : "no";
echo "\n";

// also accept $2a$ and $2b$ hashes (PHP 7+ accepts all three variants)
$alt_b = '$2b$10$ABCDEFGHIJKLMNOPQRSTUO9YJsGFAvxJzEvOwBoYLF4cXf6yPgZ.O';
$alt_a = '$2a$10$ABCDEFGHIJKLMNOPQRSTUO9YJsGFAvxJzEvOwBoYLF4cXf6yPgZ.O';
echo password_verify('mypass', $alt_b) ? "b ok" : "b no";
echo "\n";
echo password_verify('mypass', $alt_a) ? "a ok" : "a no";
echo "\n";

// password_needs_rehash
echo password_needs_rehash($h, PASSWORD_BCRYPT) ? "yes" : "no";
echo "\n";
echo password_needs_rehash($h, PASSWORD_BCRYPT, ['cost' => 14]) ? "yes" : "no";
echo "\n";

// crypt() with bcrypt salt
$h = crypt('hello', '$2y$10$abcdefghijklmnopqrstuv');
echo strlen($h) . "\n";
echo substr($h, 0, 7) . "\n";

// crypt with $2a$ salt preserves the prefix
$h = crypt('hello', '$2a$10$abcdefghijklmnopqrstuv');
echo substr($h, 0, 7) . "\n";
