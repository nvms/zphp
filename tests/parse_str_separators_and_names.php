<?php
// parse_str splits at any character of arg_separator.input, and a first [
// without its ] makes a plain name
parse_str("arr[1=sid&arr[4][2=fred&a b.c[x=1&[q=2&k]=3", $r); var_dump($r);
$code = "parse_str(\"first=val1/second=val2;third=val3&x=y\", \$r); var_dump(\$r);";
echo shell_exec(escapeshellarg(PHP_BINARY) . " -n -d arg_separator.input=/\; -r " . escapeshellarg($code));
