<?php
// a double-quoted -d value loses the backslash before ", \ and $, as php's
// ini scanner does, and keeps any other backslash
$values = ['"kill \$\$"', '"a\\\\b"', '"say \"hi\""', '"C:\\dir\\n"', 'plain\$x', '"tail\\"'];
foreach ($values as $v) {
    $cmd = escapeshellarg(PHP_BINARY) . ' -d ' . escapeshellarg("user_agent=$v") . ' -r ' . escapeshellarg('var_dump(ini_get("user_agent"));');
    echo $v, " => ", shell_exec($cmd);
}
