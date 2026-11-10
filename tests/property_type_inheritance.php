<?php
// a redeclared property keeps the type of the one it overrides; each case
// runs in its own process since the error is fatal

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'pti');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
    echo trim(str_replace($file, 'FILE', $out)), "\n";
}

run('class A { public int $p; } class B extends A { public string $p; } echo "declared\n";');
run('class A { public int $p; } class B extends A { public $p; }');
run('class A { public $p = 1; } class B extends A { public int $p = 2; }');
run('class A { protected ?int $p; } class B extends A { public ?int $p; } echo "same type\n";');
run('class A { protected int|string $p; } class B extends A { public string|int $p; } echo "same union\n";');
run('class X {} class Y extends X {} class A { public X $p; } class B extends A { public Y $p; }');
run('interface I {} interface J {} class A { public (I&J)|int $p; } class B extends A { public (I&J)|int|null $p; }');
run('class A { public mixed $p; } class B extends A { public mixed $p; } echo "mixed\n";');
run('class A { public bool|int|float|string|array|object|null $p; } class B extends A { public mixed $p; }');
run('class A { public static int $s = 1; } class B extends A { public static string $s = ""; }');
run('class A { private int $p; } class B extends A { public string $p; } echo "private parent\n";');
run('class A { public X|B $p; } class B extends A { public B $p; }');
run('class X {} class_alias("X", "Y"); class A { public X $p; } class B extends A { public Y $p; } echo "alias\n";');
run('class A { public self $p; } class B extends A { public A $p; } echo "self resolved\n";');
run('class A { public int $p; } $b = new class extends A { public float $p; };');
