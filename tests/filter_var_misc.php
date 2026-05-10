<?php
// FILTER_VALIDATE_INT
var_dump(filter_var("42", FILTER_VALIDATE_INT));        // 42
var_dump(filter_var("-42", FILTER_VALIDATE_INT));       // -42
var_dump(filter_var("0", FILTER_VALIDATE_INT));         // 0
var_dump(filter_var("abc", FILTER_VALIDATE_INT));       // false
var_dump(filter_var("1.5", FILTER_VALIDATE_INT));       // false
var_dump(filter_var("12abc", FILTER_VALIDATE_INT));     // false
var_dump(filter_var(" 12 ", FILTER_VALIDATE_INT));      // 12
var_dump(filter_var("0x10", FILTER_VALIDATE_INT));      // false
var_dump(filter_var("010", FILTER_VALIDATE_INT));       // 10 (decimal)
var_dump(filter_var(42, FILTER_VALIDATE_INT));          // 42

// FILTER_VALIDATE_INT with options
$opts = ["options" => ["min_range" => 1, "max_range" => 100]];
var_dump(filter_var(50, FILTER_VALIDATE_INT, $opts));    // 50
var_dump(filter_var(0, FILTER_VALIDATE_INT, $opts));     // false
var_dump(filter_var(101, FILTER_VALIDATE_INT, $opts));   // false

// FILTER_VALIDATE_FLOAT
var_dump(filter_var("1.5", FILTER_VALIDATE_FLOAT));     // 1.5
var_dump(filter_var("1.5e3", FILTER_VALIDATE_FLOAT));   // 1500
var_dump(filter_var("abc", FILTER_VALIDATE_FLOAT));     // false
var_dump(filter_var(".5", FILTER_VALIDATE_FLOAT));      // 0.5

// FILTER_VALIDATE_BOOLEAN
var_dump(filter_var("yes", FILTER_VALIDATE_BOOLEAN));   // true
var_dump(filter_var("no", FILTER_VALIDATE_BOOLEAN));    // false
var_dump(filter_var("on", FILTER_VALIDATE_BOOLEAN));    // true
var_dump(filter_var("off", FILTER_VALIDATE_BOOLEAN));   // false
var_dump(filter_var("1", FILTER_VALIDATE_BOOLEAN));     // true
var_dump(filter_var("0", FILTER_VALIDATE_BOOLEAN));     // false
var_dump(filter_var("true", FILTER_VALIDATE_BOOLEAN));  // true
var_dump(filter_var("false", FILTER_VALIDATE_BOOLEAN)); // false
var_dump(filter_var("maybe", FILTER_VALIDATE_BOOLEAN)); // null (or false)

// FILTER_VALIDATE_EMAIL
var_dump(filter_var("user@example.com", FILTER_VALIDATE_EMAIL));
var_dump(filter_var("invalid", FILTER_VALIDATE_EMAIL));
var_dump(filter_var("user@", FILTER_VALIDATE_EMAIL));
var_dump(filter_var("user.name+tag@sub.example.com", FILTER_VALIDATE_EMAIL));

// FILTER_VALIDATE_URL
var_dump(filter_var("https://example.com", FILTER_VALIDATE_URL));
var_dump(filter_var("not a url", FILTER_VALIDATE_URL));
var_dump(filter_var("ftp://files.example.com/path", FILTER_VALIDATE_URL));
var_dump(filter_var("http://localhost:8080", FILTER_VALIDATE_URL));

// FILTER_VALIDATE_REGEXP
$opts = ["options" => ["regexp" => "/^[A-Z]{3}$/"]];
var_dump(filter_var("ABC", FILTER_VALIDATE_REGEXP, $opts));
var_dump(filter_var("abc", FILTER_VALIDATE_REGEXP, $opts));
var_dump(filter_var("ABCD", FILTER_VALIDATE_REGEXP, $opts));

// FILTER_VALIDATE_DOMAIN
var_dump(filter_var("example.com", FILTER_VALIDATE_DOMAIN));
var_dump(filter_var("example", FILTER_VALIDATE_DOMAIN));
var_dump(filter_var("not a domain!", FILTER_VALIDATE_DOMAIN));

// FILTER_VALIDATE_IP
var_dump(filter_var("192.168.1.1", FILTER_VALIDATE_IP));
var_dump(filter_var("999.999.999.999", FILTER_VALIDATE_IP));
var_dump(filter_var("::1", FILTER_VALIDATE_IP));
var_dump(filter_var("::1", FILTER_VALIDATE_IP, FILTER_FLAG_IPV4));   // false
var_dump(filter_var("192.168.1.1", FILTER_VALIDATE_IP, FILTER_FLAG_IPV6)); // false

// FILTER_VALIDATE_MAC
var_dump(filter_var("00:11:22:33:44:55", FILTER_VALIDATE_MAC));
var_dump(filter_var("0011.2233.4455", FILTER_VALIDATE_MAC));
var_dump(filter_var("not-a-mac", FILTER_VALIDATE_MAC));
var_dump(filter_var("00-11-22-33-44-55", FILTER_VALIDATE_MAC));

// FILTER_SANITIZE_* (some deprecated in PHP 8.1)
var_dump(filter_var("hello\x00world", FILTER_SANITIZE_FULL_SPECIAL_CHARS));
var_dump(filter_var("Hello <b>World</b>", FILTER_SANITIZE_SPECIAL_CHARS));

// FILTER_SANITIZE_NUMBER_INT (kept)
var_dump(filter_var("a1b2c3", FILTER_SANITIZE_NUMBER_INT));   // "123"
var_dump(filter_var("-1.5", FILTER_SANITIZE_NUMBER_INT));     // "-15"

// FILTER_SANITIZE_NUMBER_FLOAT
var_dump(filter_var("a1.5b", FILTER_SANITIZE_NUMBER_FLOAT, FILTER_FLAG_ALLOW_FRACTION));
// FILTER_SANITIZE_EMAIL kept
var_dump(filter_var("user with space@example.com", FILTER_SANITIZE_EMAIL));

// filter_var with default
$opts = ["options" => ["default" => "fallback"]];
var_dump(filter_var("abc", FILTER_VALIDATE_INT, $opts));    // "fallback"
var_dump(filter_var("42", FILTER_VALIDATE_INT, $opts));     // 42

// filter_var_array
$data = ["age" => "30", "email" => "x@y.com", "id" => "abc"];
$rules = [
    "age" => FILTER_VALIDATE_INT,
    "email" => FILTER_VALIDATE_EMAIL,
    "id" => FILTER_VALIDATE_INT,
];
print_r(filter_var_array($data, $rules));
