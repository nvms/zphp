<?php
// a class, interface, trait or enum declared inside a method is php's
// compile error; inside a function, and as an anonymous class, it is not
$cases = [
    'class A { function f() { class B {} } }',
    'class A { function f() { interface I {} } }',
    'trait T { function f() { enum E {} } }',
    'class A { function f() { return new class {}; } } var_dump(get_class((new A)->f()) !== "");',
    'function f() { class Inner {} } f(); var_dump(class_exists("Inner"));',
];
foreach ($cases as $i => $code) {
    $file = sys_get_temp_dir() . "/zphp-nested-$i-" . getmypid() . ".php";
    file_put_contents($file, "<?php\n$code\necho 'compiled';\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    echo $code, "\n  ", trim(str_replace($file, 'FILE', $out)), "\n";
    unlink($file);
}
