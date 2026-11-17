<?php
// sodium refuses a base64 variant libsodium doesn't know (libsodium itself
// aborts the process on one) and a string that isn't base64
foreach ([1, 3, 5, 7] as $variant) {
    $b64 = sodium_bin2base64("ab\xff", $variant);
    var_dump($b64, sodium_base642bin($b64, $variant));
}
foreach ([0, 2, 8, -1] as $variant) {
    try {
        sodium_bin2base64("ab", $variant);
    } catch (SodiumException $e) {
        echo $e->getMessage(), "\n";
    }
    try {
        sodium_base642bin("YWI=", $variant);
    } catch (SodiumException $e) {
        echo $e->getMessage(), "\n";
    }
}
try {
    sodium_base642bin("Y!WI=", SODIUM_BASE64_VARIANT_ORIGINAL);
} catch (SodiumException $e) {
    echo $e->getMessage(), "\n";
}
var_dump(sodium_base642bin("Y W I=", SODIUM_BASE64_VARIANT_ORIGINAL, " "));
