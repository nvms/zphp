<?php
// a method an interface redeclares must be compatible with the one of the
// interface it extends; each case runs in its own process

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'imc');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d fatal_error_backtraces=0 ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
    echo trim(str_replace($file, 'FILE', $out)), "\n";
}

run('interface A { function f(): int; } interface B extends A { function f(): string; }');
run('interface A { function f(int $x); } interface B extends A { function f(string $x); }');
run('interface A { function f(): iterable; } interface B extends A { function f(): array; } echo "narrowed\n";');
run('interface X {} interface Y {} class T implements X, Y {} interface A { function f(): X&Y; } interface B extends A { function f(): T|int; }');
run('interface X {} interface Y {} class T implements X, Y {} interface A { function f(): X&Y; } interface B extends A { function f(): T; } echo "subtype\n";');
run('interface A { function f(); } interface C { function f($a = 1); } interface B extends A, C { function f($a = 1); } echo "two parents\n";');
run('interface A { function f($a); } interface B extends A { function f(); }');
