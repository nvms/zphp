<?php
// a typed class constant redeclared with a type naming classes that can't
// be loaded fails the inheritance check, as php's unresolved obligation does

$cases = [
    "class A1 { const ?B1 C = null; }\nclass A2 extends A1 { const ?B2 C = null; }\necho 'declared';",
    "class B {}\nclass C extends B {}\nclass A1 { const ?B C = null; }\nclass A2 extends A1 { const ?C C = null; }\necho 'declared';",
    "class A1 { const ?B1 C = null; }\nclass A2 extends A1 { const ?B1 C = null; }\necho 'declared';",
];
$file = sys_get_temp_dir() . '/zphp_const_types_' . getmypid() . '.php';
foreach ($cases as $code) {
    file_put_contents($file, "<?php\n$code\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 -d fatal_error_backtraces=0 ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace([$file, str_replace('/', DIRECTORY_SEPARATOR, $file)], 'FILE', $out), "\n";
}
unlink($file);
