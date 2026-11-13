<?php
// compile-time errors php raises for parameters, promoted properties,
// readonly classes, $this, isset(), switch and try

$cases = [
    'function f(...$a, $b) {}',
    'function f(...$a = []) {}',
    'function f(public $a) {}',
    '$f = function (private $a) {};',
    'class C { function m(public $a) {} }',
    'abstract class C { abstract function __construct(public $a); }',
    'interface I { function __construct(public $a); }',
    'class C { function __construct(public ...$a) {} }',
    'class C { function __construct(public callable $a) {} }',
    'class C { function __construct(public ?callable $a) {} }',
    'class C { function __construct(public readonly $a) {} }',
    'class C { function __construct(public private(set) $a) {} }',
    'class C { function __construct(private protected(set) string $a) {} }',
    'readonly class C { public $a; }',
    'readonly class C { public static int $a; }',
    'readonly class C { function __construct(private $a) {} }',
    'readonly class C { public int $a; function __construct(public int $b) {} } echo "ok\n";',
    '$x = new readonly class { public $a; };',
    'function f() { try { } catch (Exception $this) { } }',
    'function f() { unset($this); }',
    'function f() { global $this; }',
    'isset(1 + 1);',
    'isset(f());',
    'isset(A::B);',
    'isset($a[]);',
    'var_dump(isset($a, $b[1], $c->d, A::$e, ($f)));',
    'switch (1) { default: break; case 2: break; default: break; }',
    'function f() { try { echo 1; } }',
];
foreach ($cases as $code) {
    $file = tempnam(sys_get_temp_dir(), 'ce');
    file_put_contents($file, "<?php\n$code\n");
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    echo $code, "\n  ", trim(str_replace($file, 'FILE', $out)), "\n";
    unlink($file);
}
