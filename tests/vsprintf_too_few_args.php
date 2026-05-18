<?php
// regression: vsprintf and vprintf throw ValueError when the args array has
// fewer entries than the format string consumes. previously zphp silently
// substituted empty strings for missing values, masking bugs in caller code
try {
    vsprintf("%s %s %s", ["a", "b"]);
} catch (\ValueError $e) {
    echo "v1: " . $e->getMessage() . "\n";
}

try {
    vsprintf("%d-%d-%d-%d", [1, 2]);
} catch (\ValueError $e) {
    echo "v2: " . $e->getMessage() . "\n";
}

// positional referencing arg 5 with only 2 provided
try {
    vsprintf("%5\$s", ["a", "b"]);
} catch (\ValueError $e) {
    echo "v3: " . $e->getMessage() . "\n";
}

// %% literals don't count
echo vsprintf("100%% complete: %s", ["done"]) . "\n";

// exact arg count works
echo vsprintf("%s+%s=%s", ["a", "b", "ab"]) . "\n";

// extra args are fine
echo vsprintf("%s", ["x", "y", "z"]) . "\n";

// vprintf same enforcement
try {
    vprintf("%s %s", ["only one"]);
} catch (\ValueError $e) {
    echo "vp: " . $e->getMessage() . "\n";
}
