<?php
$pool = new Zphp\Pool(workers: 2, bootstrap: __DIR__ . "/worker.php");
var_dump($pool->workers());
$f = $pool->submit('square', [12]);
var_dump($f->await());
var_dump($pool->submit('Jobs::sum', [[1, 2, 3]])->await());
var_dump($pool->submit(['Jobs', 'sum'], [[4, 5]])->await());
try { $pool->submit('boom', ['bad input'])->await(); } catch (InvalidArgumentException $e) { echo get_class($e), ": ", $e->getMessage(), " ", $e->getCode(), "\n"; }
try { $pool->submit('missing_fn')->await(); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
var_dump($pool->submit(fn() => 1)->await());
try { $pool->submit('square', [new PDO('sqlite::memory:')]); } catch (Zphp\TransferException $e) { echo "transfer: ", $e->getMessage(), "\n"; }
$futures = [];
for ($i = 0; $i < 20; $i++) $futures[] = $pool->submit('square', [$i]);
$sum = 0; foreach ($futures as $f) $sum += $f->await();
var_dump($sum);
$slow = $pool->submit('slow', [300]);
try { $slow->await(0.05); } catch (Zphp\TimeoutException $e) { echo "timeout\n"; }
var_dump($slow->isDone(), $slow->await());
$a = $pool->submit('slow', [200]); $b = $pool->submit('slow', [200]); $c = $pool->submit('slow', [50]);
$cancelled = $c->cancel();
var_dump($cancelled);
try { $c->await(); } catch (Zphp\CancelledException $e) { echo "cancelled\n"; }
$done = []; while ($f = $pool->collect(1.0)) { $done[] = $f->id(); if (count($done) == 2) break; }
sort($done); var_dump($done);
$w = $pool->submit('who')->await(); var_dump($w['task'] > 0, $w['worker'] >= 0);
$r = $pool->readiness(); var_dump(is_resource($r) || is_object($r));
$pool->shutdown();
try { $pool->submit('square', [1]); } catch (Zphp\PoolException $e) { echo "after shutdown: ", $e->getMessage(), "\n"; }
try { new Zphp\Pool(1, __DIR__ . "/nope.php"); } catch (Zphp\PoolException $e) { echo "bad bootstrap: ", basename($e->getMessage()), "\n"; }
$p2 = new Zphp\Pool(1);
var_dump($p2->submit('strtoupper', ['hi'])->await());
echo "end\n";
