<?php
// exit() in a destructor, or in the finally block of a suspended fiber being
// destroyed, ends the script wherever the release happens: the code after it
// never runs, a catch the unwinding was heading for is skipped, and shutdown
// functions and the remaining destructors still run
$prelude = <<<'PHP'
<?php
class D {
    public $self;
    public function __construct(public string $name, public int $status = 3) {}
    public function __destruct() {
        echo "{$this->name}::__destruct\n";
        exit($this->status);
    }
}
class Quiet {
    public function __destruct() { echo "Quiet::__destruct\n"; }
}
register_shutdown_function(function () { echo "shutdown function\n"; });
function suspended(int $status): Fiber {
    $fiber = new Fiber(function () use ($status) {
        try {
            Fiber::suspend();
        } finally {
            echo "fiber finally\n";
            exit($status);
        }
    });
    $fiber->start();
    return $fiber;
}

PHP;

$cases = [
    'unset a global' => '$q = new Quiet; $d = new D("g"); unset($d); echo "not reached\n";',
    'assign null to a global' => '$d = new D("g"); $d = null; echo "not reached\n";',
    'function scope ends' => 'function f() { $d = new D("local"); } f(); echo "not reached\n";',
    'temporary' => 'new D("temp"); echo "not reached\n";',
    'unwinding to a catch' => 'function t() { $d = new D("unwound"); throw new Exception("e"); } try { t(); } catch (Exception $e) { echo "caught\n"; } echo "not reached\n";',
    'unwinding through a finally' => 'function t() { $d = new D("unwound"); throw new Exception("e"); } try { t(); } finally { echo "finally\n"; } echo "not reached\n";',
    'collected cycle' => '$d = new D("cycle"); $d->self = $d; unset($d); gc_collect_cycles(); echo "not reached\n";',
    'string status' => '$d = new D("s"); $d->status = 0; unset($d); echo "not reached\n";',
    'destroyed fiber' => '$f = suspended(4); echo "before destroy\n"; unset($f); echo "not reached\n";',
    'destroyed fiber, unwinding' => 'function t() { $f = suspended(5); echo "before destroy\n"; throw new Exception("pending"); } try { t(); } catch (Exception $e) { echo get_class($e), "\n"; } echo "not reached\n";',
    'destroyed fiber at a function end' => 'function t() { $f = suspended(6); } t(); echo "not reached\n";',
    'fiber destroyed by reassignment' => '$f = suspended(7); $f = null; echo "not reached\n";',
];

$file = tempnam(sys_get_temp_dir(), 'exd');
foreach ($cases as $name => $code) {
    echo "-- $name\n";
    file_put_contents($file, $prelude . $code);
    $proc = proc_open([PHP_BINARY, '-n', $file], [1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $pipes);
    echo stream_get_contents($pipes[1]);
    echo stream_get_contents($pipes[2]);
    echo "status ", proc_close($proc), "\n";
}
unlink($file);
