<?php
// an exponent marker must have at least one exponent digit,
// every false result below distinguishes php from the current Value.isNumericString path
var_dump("0e" == 0);
var_dump("1e" == 1);
var_dump("1e+" == 1);
var_dump("1e-" == 1);
var_dump("1E" == 1);
var_dump("1E-" == 1);

// both-string comparisons must also avoid numeric comparison
var_dump("1e" == "1");
var_dump("0e" <=> "0");
var_dump("1e" <=> "1");
var_dump("1E-" <=> "1");

// valid scientific notation remains numeric
var_dump("1e2" == 100);
var_dump("1E+2" == 100);
var_dump("1e-2" == 0.01);
var_dump("1e2" <=> "100");

// existing native is_numeric behavior is a guard, not a reason to change its code
var_dump(is_numeric("0e"));
var_dump(is_numeric("1e"));
var_dump(is_numeric("1e+"));
var_dump(is_numeric("1e-"));
var_dump(is_numeric("1E"));
var_dump(is_numeric("1E-"));
var_dump(is_numeric("1e2"));
var_dump(is_numeric("1E+2"));
var_dump(is_numeric("1e-2"));
