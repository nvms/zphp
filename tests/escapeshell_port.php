<?php
// escapeshellarg and escapeshellcmd as php's exec.c escapes
foreach (["plain", "it's", "a'b'c", "", "spa ce", "émoji ✓", "x\xffy", "a\$b`c`", 12, 1.5, true] as $arg) {
    var_dump(escapeshellarg($arg));
}
foreach ([
    "ls -la", "echo 'quoted' \"double\"", "echo 'unpaired", "a\"b'c\"d", "rm -rf * ; echo \$HOME | cat > x",
    "(sub) [x] {y} ~ ^ ? # & \\", "line\nbreak", "x\xffy", "émoji ✓ & more", "'", "\"\"", "",
] as $cmd) {
    var_dump(escapeshellcmd($cmd));
}
foreach (['escapeshellarg', 'escapeshellcmd'] as $f) {
    try {
        $f("nul\0byte");
    } catch (ValueError $e) {
        echo $e->getMessage(), "\n";
    }
}
