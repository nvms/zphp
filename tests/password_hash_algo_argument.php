<?php
// password_hash's $algo: null, the legacy numbers and the registered names
// are accepted, anything else is a ValueError
foreach ([null, 0, 1, PASSWORD_BCRYPT, PASSWORD_DEFAULT, "2y", "nope", 9, "2a", ""] as $algo) {
    try {
        $h = password_hash("secret", $algo, ["cost" => 4]);
        echo var_export($algo, true), ": ", substr($h, 0, 7), " ", var_export(password_verify("secret", $h), true), "\n";
    } catch (ValueError $e) {
        echo var_export($algo, true), ": ", $e->getMessage(), "\n";
    }
}
