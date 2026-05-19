<?php
// regression: hash('joaat', ...) implements the Jenkins one-at-a-time hash.
// previously zphp threw ValueError 'must be a valid hashing algorithm' on
// joaat - some PHP code uses joaat as a fast non-cryptographic 32-bit hash
// for ID generation and dedup keys
echo hash('joaat', 'hello') . "\n";
echo hash('joaat', '') . "\n";
echo hash('joaat', 'The quick brown fox jumps over the lazy dog') . "\n";
echo hash('joaat', str_repeat('a', 256)) . "\n";
echo bin2hex(hash('joaat', 'raw', true)) . "\n";

// hash_algos includes joaat
echo in_array('joaat', hash_algos()) ? "y\n" : "n\n";
