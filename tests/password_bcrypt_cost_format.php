<?php
// a bcrypt hash counts as one only with "$2y$", two cost digits from 04 to
// 31 and "$" at the start of 60 bytes; anything else is unknown to
// password_get_info() and always needs a rehash
$tail = str_repeat('a', 53);
$hashes = [
    'valid 10' => '$2y$10$' . $tail,
    'valid 04' => '$2y$04$' . $tail,
    'valid 31' => '$2y$31$' . $tail,
    'cost 03' => '$2y$03$' . $tail,
    'cost 32' => '$2y$32$' . $tail,
    'cost 99' => '$2y$99$' . $tail,
    'non-digit' => '$2y$1a$' . $tail,
    'space' => '$2y$ 9$' . $tail,
    'sign' => '$2y$+9$' . $tail,
    'malformed separator' => '$2y$10x' . $tail,
    'missing separator' => '$2y$1' . str_repeat('a', 55),
    'three digits' => '$2y$100' . $tail,
    'short' => '$2y$10$' . substr($tail, 1),
    'long' => '$2y$10$' . $tail . 'a',
    '2a' => '$2a$10$' . $tail,
];

foreach ($hashes as $name => $hash) {
    $info = password_get_info($hash);
    echo str_pad($name, 20), json_encode($info), ' rehash(10): ';
    var_dump(password_needs_rehash($hash, PASSWORD_BCRYPT, ['cost' => 10]));
}

// verification still reads the hash as bcrypt
$real = password_hash('secret', PASSWORD_BCRYPT, ['cost' => 4]);
var_dump(password_verify('secret', $real), password_needs_rehash($real, PASSWORD_BCRYPT, ['cost' => 4]));
var_dump(password_get_info($real)['options']);
var_dump(password_verify('secret', substr_replace($real, '03', 4, 2)));
