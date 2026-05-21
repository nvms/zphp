<?php
// regression: referencing an undefined bareword constant is a fatal Error in
// PHP 8, not a silent null. zphp's get_var resolved an unknown bareword to
// null, so `UNDEFINED ?? x` wrongly yielded x and `echo UNDEFINED` printed
// nothing instead of throwing.

// undefined constant throws a catchable Error
try {
    echo NOT_A_REAL_CONSTANT;
    echo "unreachable\n";
} catch (Error $e) {
    echo "caught: ", $e->getMessage(), "\n";
}

// the null-coalescing operator does NOT suppress it (?? only covers
// undefined variables, array keys, and properties)
try {
    $x = ALSO_UNDEFINED ?? 'fallback';
    echo "unreachable\n";
} catch (Error $e) {
    echo "coalesce still throws: ", $e->getMessage(), "\n";
}

// defined constants resolve normally
define('REAL_ONE', 42);
echo REAL_ONE, "\n";

const REAL_TWO = 'hello';
echo REAL_TWO, "\n";

// built-in constants still work
echo PHP_INT_MAX, "\n";
echo PHP_EOL === "\n" ? "eol-ok\n" : "eol-bad\n";
echo M_PI > 3.14 && M_PI < 3.15 ? "pi-ok\n" : "pi-bad\n";

// defined() guards a conditional reference without throwing
echo defined('STILL_MISSING') ? STILL_MISSING : "absent\n";

// case sensitivity: constants are case-sensitive
define('CaseTest', 'exact');
echo CaseTest, "\n";
try {
    echo CASETEST;
} catch (Error $e) {
    echo "case-sensitive: ", $e->getMessage(), "\n";
}

// undefined variables are still a silent null, not an error
$y = $undefined_variable ?? 'var-fallback';
echo $y, "\n";
