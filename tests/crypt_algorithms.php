<?php
// crypt() with each of php's own algorithms, its failure tokens, and the
// password_* functions built on it

$salts = [
    'ab', '_J9..SDiz', '_K9..Salt', '$1$rasmusle$', '$1$', '$1$toolongsaltvalue',
    '$5$saltstring', '$5$rounds=1000$abc', '$5$rounds=10$abc', '$5$rounds= +2000$xy',
    '$5$rounds=1000000000$', '$6$saltstring', '$6$rounds=1400$anotherlongsaltstring',
    '$6$rounds=-5$x', '$6$rounds=abc$x', '$2y$04$abcdefghijklmnopqrstuu',
    '$2a$04$abcdefghijklmnopqrstuv', '$2x$04$abcdefghijklmnopqrstuu',
    '$2b$04$abcdefghijklmnopqrstuu', '$2c$04$abcdefghijklmnopqrstuu',
    '$2y$03$abcdefghijklmnopqrstuu', '$2y$32$abcdefghijklmnopqrstuu',
    '$2y$04$abcdefghijklmnopqrst!u', '*0', '*1', '', 'a', '!!', "a\0b", '$7$x',
];
foreach (['', 'U*U', 'password', "\xff\xa3" . "345", "pass\0word", str_repeat('x', 80)] as $pw) {
    foreach ($salts as $salt) {
        echo json_encode($salt), ' => ', crypt($pw, $salt), "\n";
    }
}

foreach (['$2y$04$', '$1$rasmusle$rISCgZzpwk3UhDidwXvin0', 'rl.3StKT.4T8M', '$2y$1', '$x$', 'x'] as $hash) {
    var_dump(password_verify('rasmuslerdorf', $hash));
    var_dump(password_get_info($hash));
}

$h = password_hash('secret', PASSWORD_BCRYPT, ['cost' => 5]);
var_dump(strlen($h), substr($h, 0, 7), password_verify('secret', $h), password_verify('Secret', $h));
var_dump(password_needs_rehash($h, PASSWORD_BCRYPT, ['cost' => 5]));
var_dump(password_needs_rehash($h, PASSWORD_BCRYPT));
var_dump(password_needs_rehash($h, 'nope'));
var_dump(password_needs_rehash($h, PASSWORD_ARGON2ID));

$a = password_hash('secret', PASSWORD_ARGON2ID, ['memory_cost' => 1024, 'time_cost' => 2, 'threads' => 2]);
var_dump(substr($a, 0, 30), password_verify('secret', $a), password_verify('other', $a));
var_dump(password_get_info($a));
var_dump(password_needs_rehash($a, PASSWORD_ARGON2ID, ['memory_cost' => 1024, 'time_cost' => 2, 'threads' => 2]));
var_dump(password_get_info('$argon2i$v=19$m=65536'));
var_dump(password_algos());

foreach ([[PASSWORD_BCRYPT, ['cost' => 3]], [PASSWORD_BCRYPT, ['cost' => '32']], ['nope', []], [7, []], [PASSWORD_ARGON2I, ['memory_cost' => -1]], [PASSWORD_ARGON2I, ['threads' => 4, 'memory_cost' => 16]], [[], []]] as [$algo, $opts]) {
    try {
        password_hash('x', $algo, $opts);
    } catch (Throwable $e) {
        echo get_class($e), ': ', $e->getMessage(), "\n";
    }
}
try {
    password_hash("a\0b", PASSWORD_BCRYPT);
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
var_dump(strlen(password_hash('x', PASSWORD_BCRYPT, ['cost' => 4, 'salt' => 'ignored'])));
var_dump(PASSWORD_BCRYPT_DEFAULT_COST, PASSWORD_ARGON2_DEFAULT_MEMORY_COST, PASSWORD_ARGON2_DEFAULT_TIME_COST, PASSWORD_ARGON2_DEFAULT_THREADS, PASSWORD_ARGON2_PROVIDER);
var_dump(CRYPT_SALT_LENGTH, CRYPT_STD_DES, CRYPT_EXT_DES, CRYPT_MD5);
