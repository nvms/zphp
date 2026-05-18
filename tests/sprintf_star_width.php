<?php
// regression: sprintf accepts '*' as a width specifier that consumes the
// next argument as the dynamic width (matching PHP's printf-style support).
// previously zphp raised 'Unknown format specifier "*"' and aborted.
// dynamic precision via '.*' was already supported
echo sprintf("%*d", 8, 42) . "\n";          // "      42"
echo sprintf("%-*d|", 6, 42) . "\n";        // "42    |"
echo sprintf("%*.2f", 10, 3.14159) . "\n";  // "      3.14"
echo sprintf("%0*d", 5, 7) . "\n";          // "00007"
echo sprintf("%*s", 6, "hi") . "\n";        // "    hi"

// dynamic precision still works
echo sprintf("%.*f", 3, 3.14159) . "\n";    // "3.142"
echo sprintf("%.*s", 4, "abcdef") . "\n";   // "abcd"

// both * width and .* precision in one format
echo sprintf("%*.*f", 10, 3, 3.14159) . "\n";

// vsprintf accounts for * in arg count
echo vsprintf("%*d %*d", [5, 1, 5, 2]) . "\n";

// vsprintf throws when * args are missing (exact required count is
// PHP-version-specific; just verify ValueError is raised)
try {
    vsprintf("%*d %*d", [5, 1]);
    echo "vs-no-throw\n";
} catch (\ValueError $e) {
    echo "vs-too-few: " . get_class($e) . "\n";
}
