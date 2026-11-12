<?php
// version_compare canonicalizes both strings and compares them part by part
// as php_version_compare does, and refuses an unknown operator
$versions = ["1", "1.0", "1.0.0", "1.0rc1", "1.0RC1", "1.0-dev", "1.0alpha", "1.0a", "1.0b2", "1.0beta",
    "1.0pl1", "1.0p1", "1.0#1", "1.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.0.1", "5.2", "5.10", "1.0+1", "1.0_1",
    ".1", "#a", "", "abc", "1.0x", "99999999999999999999", "1-2-3"];
foreach ($versions as $a) {
    $row = [];
    foreach ($versions as $b) {
        $row[] = version_compare($a, $b);
    }
    echo str_pad(json_encode($a), 40), implode(" ", $row), "\n";
}
foreach (["<", "lt", "<=", "le", ">", "gt", ">=", "ge", "==", "=", "eq", "!=", "<>", "ne"] as $op) {
    var_dump(version_compare("1.0", "1.1", $op));
}
foreach (["", "l", "g", "e", "!", "n", "LT"] as $op) {
    try {
        version_compare("1", "2", $op);
        echo "'$op' accepted\n";
    } catch (ValueError $e) {
        echo "'$op': ", $e->getMessage(), "\n";
    }
}
