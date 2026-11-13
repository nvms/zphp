<?php
// a class or method named by a constant that isn't a string is a compile
// error; strings, names and variables still compile

$cases = [
    '(0)::t;', '(-0)::$prop;', '[]::X::X;', '(1.5)::f();', '[1, 2]::$p;', '(-(1))::{"x"}();',
    '$o->{0}();', '$o->{1.0}();', '$o->{true}();', '$o->{null}(...[]);', 'C::{false}();', 'C::{[]}();',
    '$o->{"f"}();', 'C::{"f"}();', '$c::f();',
];
class C {
    public static function f() { return 'f'; }
    public static $p = 1;
}
foreach ($cases as $code) {
    $file = tempnam(sys_get_temp_dir(), 'icn');
    file_put_contents($file, "<?php\nclass C { static function f() { return 'f'; } }\n\$o = new C; \$c = 'C';\nvar_dump(" . rtrim($code, ";") . ");\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -n -d display_errors=1 ' . escapeshellarg($file) . ' 2>&1');
    echo $code, ' => ', trim(str_replace($file, 'FILE', $out)), "\n";
    unlink($file);
}
