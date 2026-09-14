<?php
// single thread: a bounded queue with value semantics for what crosses it
$ch = new Zphp\Channel(capacity: 3);
var_dump($ch->capacity(), count($ch), $ch->isClosed(), $ch instanceof Iterator, $ch instanceof Countable);
$ch->send("a"); $ch->send(["k" => 2]); $ch->send(null);
var_dump(count($ch), $ch->trySend(4));
var_dump($ch->recv(), $ch->recv(), $ch->recv());
try { $ch->recv(0.05); } catch (Zphp\TimeoutException $e) { echo "recv timeout: ", $e->getMessage(), "\n"; }
$ch->send("last");
$ch->close();
var_dump($ch->isClosed(), $ch->recv());
try { $ch->recv(); } catch (Zphp\ChannelException $e) { echo "recv closed: ", $e->getMessage(), "\n"; }
try { $ch->send(1); } catch (Zphp\ChannelException $e) { echo "send closed: ", $e->getMessage(), "\n"; }
try { $ch->trySend(1); } catch (Zphp\ChannelException $e) { echo "trySend closed: ", $e->getMessage(), "\n"; }
try { new Zphp\Channel(0); } catch (Zphp\ChannelException $e) { echo "bad capacity: ", $e->getMessage(), "\n"; }
try { (new Zphp\Channel)->send(fn() => 1); } catch (Zphp\TransferException $e) { echo "transfer: ", $e->getMessage(), "\n"; }
try { clone $ch; } catch (Error $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }

// a full channel refuses a non-blocking send and times out a bounded one
$full = new Zphp\Channel(1);
$full->send("x");
try { $full->send("y", 0.05); } catch (Zphp\TimeoutException $e) { echo "send timeout: ", $e->getMessage(), "\n"; }
var_dump($full->trySend("y"), $full->recv(), $full->trySend("y"), $full->recv());

// iteration drains a closed channel, keys count from zero per consumer
$it = new Zphp\Channel(5);
foreach ([1, 2, 3] as $n) $it->send($n * 10);
$it->close();
foreach ($it as $k => $v) echo "$k => $v\n";

// a channel crosses as its id and binds to the same channel; a stale id is an error
$again = unserialize(serialize($it));
var_dump($again->isClosed(), $again->id() === $it->id());
try { unserialize('O:12:"Zphp\Channel":1:{s:2:"id";i:999999;}'); } catch (Zphp\ChannelException $e) { echo "stale: ", $e->getMessage(), "\n"; }
$carrier = new Zphp\Channel(1);
$inner = new Zphp\Channel(1);
$carrier->send(['inner' => $inner]);
unset($inner);
$got = $carrier->recv();
$got['inner']->send("through a copy");
var_dump($got['inner']->recv());

// across threads
$pool = new Zphp\Pool(workers: 2, bootstrap: __DIR__ . "/worker.php");

// fan out jobs to two consumers, collect on a second channel
$jobs = new Zphp\Channel(4);
$results = new Zphp\Channel(100);
$a = $pool->submit('consume', [$jobs, $results]);
$b = $pool->submit('consume', [$jobs, $results]);
for ($i = 1; $i <= 20; $i++) $jobs->send($i);
$jobs->close();
var_dump($a->await() + $b->await());
$results->close();
$sum = 0; $workers = []; foreach ($results as $r) { $sum += $r['sq']; $workers[$r['worker']] = true; }
var_dump($sum, count($workers));

// a worker produces, main iterates, capacity one keeps them in step
$stream = new Zphp\Channel(1);
$p = $pool->submit('produce', [$stream, 50]);
$seen = []; foreach ($stream as $k => $v) $seen[$k] = $v;
var_dump(count($seen), $seen[0], $seen[49], $p->await());

// a pipeline of three stages
$s1 = new Zphp\Channel(2); $s2 = new Zphp\Channel(2); $s3 = new Zphp\Channel(2);
$pool->submit('forward', [$s1, $s2]); $pool->submit('forward', [$s2, $s3]);
foreach (["x", "y", "z"] as $v) $s1->send($v);
$s1->close();
var_dump(implode(",", iterator_to_array($s3, false)));

// a worker blocked in recv sees the timeout, then a value, then the close
$c = new Zphp\Channel(1);
var_dump($pool->submit('wait_recv', [$c, 0.05])->await());
$w = $pool->submit('wait_recv', [$c, 5]); usleep(50000); $c->send("late"); var_dump($w->await());
$w = $pool->submit('wait_recv', [$c, 5]); usleep(50000); $c->close(); var_dump($w->await());

// a channel created in a worker comes back in a result and outlives the worker's wrapper
$r = $pool->submit('make_channel')->await();
var_dump($r['ch'] instanceof Zphp\Channel, $r['ch']->recv());

// main drops its wrapper while a worker still consumes
$d = new Zphp\Channel(2);
$f = $pool->submit('slow_drain', [$d]);
$d->send(1); $d->send(2); $d->send(3); $d->close();
unset($d);
var_dump($f->await());

// a result that cannot cross fails the task with the path
try { $pool->submit('bad_result')->await(); } catch (Zphp\TransferException $e) { echo "result: ", $e->getMessage(), "\n"; }

$pool->shutdown();
echo "end\n";
