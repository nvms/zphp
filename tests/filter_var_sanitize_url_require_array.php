<?php
// regression: FILTER_SANITIZE_URL strips chars outside the URL-reserved
// set (spaces, control bytes), and FILTER_REQUIRE_ARRAY / FILTER_FORCE_ARRAY
// apply the inner filter to each element of an input array

echo filter_var("a b c", FILTER_SANITIZE_URL) . "\n";
echo filter_var("https://exa mple.com/p ath?q=1&r=2", FILTER_SANITIZE_URL) . "\n";
echo filter_var("x\tx\nx", FILTER_SANITIZE_URL) . "\n";
echo filter_var("safe-chars_~$@!*", FILTER_SANITIZE_URL) . "\n";

// FILTER_REQUIRE_ARRAY: per-element apply
print_r(filter_var([1, 2, "abc"], FILTER_VALIDATE_INT, FILTER_REQUIRE_ARRAY));
print_r(filter_var(["alice@x.com", "not email"], FILTER_VALIDATE_EMAIL, FILTER_REQUIRE_ARRAY));
// preserve string keys
print_r(filter_var(['a' => '1', 'b' => 'bad'], FILTER_VALIDATE_INT, FILTER_REQUIRE_ARRAY));

// REQUIRE_ARRAY on non-array returns false (the default)
var_dump(filter_var("scalar", FILTER_VALIDATE_INT, FILTER_REQUIRE_ARRAY));

// FORCE_ARRAY wraps scalar in single-element array
print_r(filter_var("42", FILTER_VALIDATE_INT, FILTER_FORCE_ARRAY));
print_r(filter_var([1, 2], FILTER_VALIDATE_INT, FILTER_FORCE_ARRAY));
