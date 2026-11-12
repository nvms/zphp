<?php
enum Plain { case A; }
enum Num: int { case One = 1; }
var_dump(json_encode(Plain::A), json_last_error() === JSON_ERROR_NON_BACKED_ENUM, json_last_error_msg());
try {
    json_encode([Plain::A], JSON_THROW_ON_ERROR);
} catch (JsonException $e) {
    echo get_class($e), ': ', $e->getMessage(), ' ', $e->getCode(), "\n";
}
var_dump(json_encode(['n' => Num::One]), json_last_error_msg());
var_dump(JSON_ERROR_RECURSION, JSON_ERROR_INF_OR_NAN, JSON_ERROR_UNSUPPORTED_TYPE, JSON_ERROR_INVALID_PROPERTY_NAME, JSON_ERROR_UTF16);
