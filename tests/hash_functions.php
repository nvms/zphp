<?php

// hash with various algorithms
echo hash("sha256", "hello") . "\n";
echo hash("md5", "hello") . "\n";
echo hash("sha1", "hello") . "\n";
echo hash("sha384", "hello") . "\n";
echo hash("sha512", "hello") . "\n";

// hash_hmac
echo hash_hmac("sha256", "hello", "secret") . "\n";
echo hash_hmac("sha1", "data", "key") . "\n";
echo hash_hmac("md5", "message", "key") . "\n";

// empty string hashing
echo hash("sha256", "") . "\n";
echo hash_hmac("sha256", "", "key") . "\n";
