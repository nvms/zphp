<?php
// suspended fibers a frame held are destroyed in order when it ends: an
// exception unwinding inside one leaves the fibers queued before it for
// later, and the next one's exception takes it as its previous
function mk($n) {
    $f = new Fiber(function () use ($n): void {
        try {
            Fiber::suspend();
        } finally {
            echo "finally $n\n";
            throw new Exception($n);
        }
    });
    $f->start();
    return $f;
}
function chain(Throwable $e) {
    $parts = [];
    for (; $e; $e = $e->getPrevious()) $parts[] = $e->getMessage();
    return implode(' <- ', $parts);
}
function scope() {
    $a = mk('first');
    $b = mk('second');
    $c = mk('third');
}
try { scope(); } catch (Exception $e) { echo chain($e), "\n"; }
