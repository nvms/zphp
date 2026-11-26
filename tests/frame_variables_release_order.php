<?php
// a frame's variables are released in their compiled order when it ends,
// also when the frame keeps a variable table (zend_free_compiled_variables)
function chain(Throwable $e) {
    $parts = [];
    for (; $e; $e = $e->getPrevious()) $parts[] = $e->getMessage();
    return implode(' <- ', $parts);
}
$fiber = new Fiber(function (): void {
    $fiber1 = new Fiber(function (): void {
        try {
            Fiber::suspend();
        } finally {
            echo "finally 1\n";
            throw new Exception('test1');
        }
    });
    $fiber1->start();
    $fiber2 = new Fiber(function (): void {
        try {
            Fiber::suspend();
        } finally {
            echo "finally 2\n";
            throw new Exception('test2');
        }
    });
    $fiber2->start();
    Fiber::suspend();
});
$fiber->start();
try {
    unset($fiber);
} catch (Exception $e) {
    echo chain($e), "\n";
}

class D {
    public function __construct(public string $n) {}
    public function __destruct() { echo "destruct {$this->n}\n"; }
}
function withTable() {
    $a = new D('a');
    $b = new D('b');
    $name = 'c';
    $$name = new D('c');
    $c2 = new D('d');
    $z = new D('z');
}
withTable();
