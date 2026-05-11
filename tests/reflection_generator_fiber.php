<?php
// covers: ReflectionGenerator + ReflectionFiber

function counter(int $n) {
    for ($i = 0; $i < $n; $i++) yield $i;
}

$g = counter(5);
$g->current();

$r = new ReflectionGenerator($g);
echo "fn name: ", $r->getFunction()->getName(), "\n";
echo "this: ", $r->getThis() === null ? 'null' : 'object', "\n";
echo "line>0: ", $r->getExecutingLine() > 0 ? 'y' : 'n', "\n";
echo "trace count: ", count($r->getTrace()), "\n";

$g2 = $r->getExecutingGenerator();
echo "exec gen current: ", $g2->current(), "\n";

// class method generators expose $this
class Series {
    public function up(int $n) {
        for ($i = 1; $i <= $n; $i++) yield $i;
    }
}
$s = new Series();
$gm = $s->up(3);
$gm->current();
$rm = new ReflectionGenerator($gm);
echo "method this: ", $rm->getThis() instanceof Series ? 'series' : 'wrong', "\n";

// Fibers
$f = new Fiber(function() {
    Fiber::suspend('paused');
});
$f->start();
$rf = new ReflectionFiber($f);
echo "fib line>0: ", $rf->getExecutingLine() > 0 ? 'y' : 'n', "\n";
echo "fib callable: ", is_callable($rf->getCallable()) ? 'y' : 'n', "\n";
echo "fib getFiber same: ", $rf->getFiber() === $f ? 'y' : 'n', "\n";
$f->resume();
