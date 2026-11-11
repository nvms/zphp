<?php
// the property and hook declarations php refuses; each case runs in its own
// process since the errors are fatal

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'phd');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 ' . escapeshellarg($file) . ' 2>&1');
    unlink($file);
    echo trim(str_replace($file, 'FILE', $out)), "\n";
}

run('class Test { final private $prop; }');
run('readonly class C { public int $prop { set => $value; } }');
run('class Test { public $prop { set(string $prop) {} } }');
run('class Test { public $prop { set(mixed $prop) {} } } echo "mixed is fine\n";');
run('class A { public $prop { get {} set {} } } class B extends A { public $prop = 0 { get {} set {} } }');
run('class A { public $prop; } class B extends A { public $prop = 0 { get => 1; set {} } } echo "backed by A\n";');
run('class A { public $prop; } class B extends A { private $_p; public $prop { &get => $this->_p; set { $this->_p = $value; } } }');
run('class B { private $_p; public $prop { &get => $this->_p; set { $this->_p = $value; } } } echo "virtual may return by reference\n";');
run('abstract class P { protected abstract int $prop { get; set; } } class C extends P { public function __construct(protected readonly int $prop) {} } echo "declared\n";');
