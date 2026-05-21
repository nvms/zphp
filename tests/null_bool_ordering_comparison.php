<?php
// regression: ordering comparisons (<, >, <=, >=, <=>) where either operand
// is null or bool convert BOTH sides to bool (FALSE < TRUE), matching PHP.
// zphp previously used numeric coercion, so `null < -1` was false (0 < -1)
// instead of true (false < true).

var_dump(null < -1);      // true  (false < true)
var_dump(null > -1);      // false
var_dump(null <= -5);     // true
var_dump(null >= -5);     // false
var_dump(null <=> -1);    // -1
var_dump(false < -1);     // true
var_dump(false <=> -3);   // -1
var_dump(true > -1);      // false (true > true)
var_dump(true < -1);      // false
var_dump(null < -0.5);    // true
var_dump(null < "x");     // true  (null-vs-string: "" < "x")
var_dump(null < 0);       // false (false < false)
var_dump(null < 1);       // true
var_dump(null <= 0);      // true
var_dump(true <=> false); // 1
var_dump(false <=> true); // -1
var_dump(true <=> true);  // 0
var_dump(null <=> false); // 0
var_dump(null <=> null);  // 0

// equality is unchanged (already correct)
var_dump(null == -1);     // false
var_dump(null == 0);      // true
var_dump(true == -1);     // true
var_dump(false == 0);     // true

// plain numeric ordering is unaffected
var_dump(5 <=> 3, 3 <=> 5, 5 <=> 5);
var_dump(-5 < -3, 2 > 1, 1.5 <= 1.5);
var_dump("abc" < "abd", "10" <=> "9");

// bool vs string
var_dump(true < "abc");   // false (true < true)
var_dump(false < "abc");  // true  (false < true)
