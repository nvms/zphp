<?php
// compile-time errors php raises for destructuring targets, empty array
// elements and the order of named, unpacked and positional arguments

$cases = [
    "['a' => \$a, , 'b' => \$b] = ['a' => 1, 'b' => 2];",
    "[, 'a' => \$b] = [1, 'a' => 2];",
    "[\$a, 'k' => \$b] = [1];",
    "['k' => \$a, \$b] = [1];",
    "[\$head, ...\$tail] = [1, 2, 3];",
    "[...\$x] = [1];",
    "[array(\$a)] = [array(42)];",
    "list(\$a, , \$b) = [1, 2, 3]; echo \$a, \$b, \"\\n\";",
    "\$a = [\n    1,\n    2,\n    ,\n    3,\n];",
    "\$a = [, 1];",
    "function t(\$a = 0, \$b = 0) {}\nt(a: 1, 2);",
    "function t(\$a = 0, \$b = 0) {}\nt(a: 42, ...[]);",
    "var_dump(...[1, 2, 3], 4);",
    "function t(...\$a) { var_dump(\$a); }\nt(1, ...[2], ...[3], a: 4);",
    "class P { function __construct(\$x = 0, \$y = 0) {} }\nnew P(x: 1, 2);",
];
foreach ($cases as $code) {
    $file = tempnam(sys_get_temp_dir(), 'cd');
    file_put_contents($file, "<?php\n$code\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    echo $code, "\n  ", trim(str_replace($file, 'FILE', $out)), "\n";
    unlink($file);
}
