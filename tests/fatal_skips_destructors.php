<?php
// a fatal error ends the script without destructors, also for the objects
// the unwinding frames release; ob_start() inside a running handler is that
// fatal even when its callback is invalid

function run(string $code): void
{
    $file = tempnam(sys_get_temp_dir(), 'fatal');
    file_put_contents($file, "<?php\n" . $code);
    $out = shell_exec(escapeshellarg(PHP_BINARY) . ' -d display_errors=1 -d log_errors=0 -d zend.exception_ignore_args=1 ' . escapeshellarg($file) . ' 2>&1');
    echo str_replace($file, 'FILE', $out), "\n";
    unlink($file);
}

run(<<<'PHP'
class D { function __construct(public $n) {} function __destruct() { echo "dtor {$this->n}\n"; } }
function f() { $o = new D('local'); ob_start(function ($b) { ob_start(); return $b; }, 1); echo "x"; }
$g = new D('global');
f();
PHP);

run(<<<'PHP'
class Test {
    public function __destruct() { echo "destructed\n"; ob_start(static function () {}); }
    public function __invoke($x) { ob_start('no_such_function'); return $x; }
}
ob_start(new Test, 1);
echo "trigger";
PHP);
