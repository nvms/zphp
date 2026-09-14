<?php
require __DIR__ . '/worker.php';
$pool = new Zphp\Pool(2, __DIR__ . '/worker.php');

// use captures by value, arrow functions capturing the caller's scope, static closures
$factor = 7;
var_dump($pool->submit(function (int $x) use ($factor) { return $x * $factor; }, [6])->await());
$offset = 100;
var_dump($pool->submit(fn(int $x) => $x + $offset + helper(1), [1])->await());
var_dump($pool->submit(static fn() => Zphp\Task::worker() >= 0)->await());

// $this and scope travel with the closure
$c = new Counter(10);
$bound = (function (int $n) { return $this->bump($n) . " / " . $this->secret(); })->bindTo($c, Counter::class);
var_dump($pool->submit($bound, [5])->await());
var_dump($pool->submit((new Maker(4))->job(), [11])->await());

// closures that create closures
$nested = function (array $xs) { $sq = fn($v) => $v * $v; return array_map($sq, array_map(function ($v) { return $v + 1; }, $xs)); };
var_dump($pool->submit($nested, [[1, 2, 3]])->await());

// the same closure submitted many times loads once per worker
$futures = []; for ($i = 0; $i < 50; $i++) $futures[] = $pool->submit(function (int $i) use ($factor) { return $i * $factor; }, [$i]);
$sum = 0; foreach ($futures as $f) $sum += $f->await(); var_dump($sum);

// exceptions, type coercion, and refusals
try { $pool->submit(function () { throw new DomainException("inside", 3); })->await(); } catch (DomainException $e) { echo get_class($e), ": ", $e->getMessage(), " ", $e->getCode(), "\n"; }
try { $pool->submit(function (string $s) { return $s; }, [5])->await(); echo "coerced\n"; } catch (TypeError $e) { echo "TypeError\n"; }
$byref = 1; try { $pool->submit(function () use (&$byref) { return $byref; }); } catch (Zphp\TransferException $e) { echo "refused: ", $e->getMessage(), "\n"; }
try { $pool->submit(function () { return fn() => 1; })->await(); } catch (Zphp\TransferException $e) { echo "result: ", $e->getMessage(), "\n"; }
$pdo = new PDO('sqlite::memory:'); try { $pool->submit(function () use ($pdo) { return 1; }); } catch (Zphp\TransferException $e) { echo "capture: ", $e->getMessage(), "\n"; }
try { $pool->submit(function () { return 1; }, [fn() => 2]); } catch (Zphp\TransferException $e) { echo "args: ", $e->getMessage(), "\n"; }

// a closure consuming a channel
$ch = new Zphp\Channel(4);
$w = $pool->submit(function (Zphp\Channel $ch) use ($factor) { $n = 0; foreach ($ch as $v) $n += $v * $factor; return $n; }, [$ch]);
foreach ([1, 2, 3] as $v) $ch->send($v); $ch->close(); var_dump($w->await());

$pool->shutdown();
echo "end\n";
