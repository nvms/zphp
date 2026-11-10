<?php
// the property declarations php refuses while compiling; each case runs in
// its own process since the error is fatal

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'pdc');
    file_put_contents($file, "<?php\necho \"start\\n\";\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
    echo trim(str_replace($file, 'FILE', $out)), "\n";
}

run('class A { public int $p = "x"; }');
run('class A { public array $p = 1; }');
run('class A { public int $p = null; }');
run('class A { public stdClass $p = null; }');
run('class A { public int|float $p = "x"; }');
run('interface X {} interface Y {} class A { public X&Y $p = null; }');
run('class A { public void $p; }');
run('class A { public never $p; }');
run('class A { public ?callable $p; }');
run('class A { public static int $p = 1.5; }');
run('class A { public float $f = 1; public ?int $n = null; public int|string $u = 2; } var_dump(new A);');
run('if (false) { class A { public bool $p = []; } } echo "unreached class\n";');
