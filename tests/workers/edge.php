<?php
$pool = new Zphp\Pool(workers: 2, bootstrap: __DIR__ . "/worker.php", queue: 2);

// a class only the worker defines arrives as a TaskException naming it
try { $pool->submit('throw_local')->await(); } catch (Zphp\TaskException $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }

// worker state persists between tasks on the same worker
$one = new Zphp\Pool(workers: 1, bootstrap: __DIR__ . "/worker.php");
var_dump($one->submit('counter')->await(), $one->submit('counter')->await());
$one->shutdown();

// backpressure: with two workers busy and a queue of two, the third trySubmit is refused
$busy = [$pool->submit('slow', [300]), $pool->submit('slow', [300])];
$queued = [$pool->submit('slow', [10]), $pool->submit('slow', [10])];
var_dump($pool->trySubmit('slow', [10]));
foreach (array_merge($busy, $queued) as $f) $f->await();
var_dump($pool->trySubmit('square', [3]) !== null);

// cooperative cancellation reaches a running task
$loop = $pool->submit('until_cancelled');
usleep(50000);
var_dump($loop->cancel(), $loop->await());

// shutdown with a timeout reports tasks still running, then waits without one
$a = $pool->submit('slow', [200]);
$b = $pool->submit('slow', [200]);
$c = $pool->submit('slow', [200]);
$d = $pool->submit('slow', [200]);
var_dump($pool->shutdown(0.01));
try { $d->await(); } catch (Zphp\CancelledException $e) { echo "queued task cancelled by shutdown\n"; }
var_dump($pool->shutdown());
var_dump($a->await(), $b->await());

// output written by a task reaches stdout
$p = new Zphp\Pool(1, __DIR__ . "/worker.php");
$p->submit('echoes', ['from a worker'])->await();

// a bootstrap that throws fails the constructor with its message
file_put_contents(__DIR__ . "/bad_bootstrap.php", "<?php throw new LogicException('bootstrap broke');");
try { new Zphp\Pool(2, __DIR__ . "/bad_bootstrap.php"); } catch (Zphp\PoolException $e) { echo "PoolException: ", $e->getMessage(), "\n"; }
unlink(__DIR__ . "/bad_bootstrap.php");

// pools come and go
for ($i = 0; $i < 20; $i++) { $t = new Zphp\Pool(2); $t->submit('strrev', ['abc'])->await(); $t->shutdown(); }
echo "20 pools\n";

// the readiness stream wakes stream_select when a task completes
$sel = new Zphp\Pool(1, __DIR__ . "/worker.php");
$f = $sel->submit('slow', [50]);
$r = [$sel->readiness()]; $w = null; $e = null;
$n = stream_select($r, $w, $e, 5);
var_dump($n, $sel->collect(0) === $f);
$sel->shutdown();
echo "end\n";
