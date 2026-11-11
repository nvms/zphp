<?php
// exec() keeps each line of the output less its trailing whitespace, and
// returns the last one
foreach (["printf 'abc\\f\\n \\n'", "printf 'a  \\nb\\t\\n\\nc'", "printf ''", "printf '\\n\\n'", "printf 'x\\r\\ny'"] as $cmd) {
    $out = [];
    $last = exec($cmd, $out, $code);
    var_dump($last, $out, $code);
    var_dump(exec($cmd));
}
