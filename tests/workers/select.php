<?php
function attempt(callable $f): void {
    try { var_dump($f()); } catch (Throwable $e) { echo get_class($e), ": ", $e->getMessage(), "\n"; }
}

// the ready source comes back with its key, and its value is received
$a = new Zphp\Channel(4);
$b = new Zphp\Channel(4);
$b->send(['n' => 1]);
var_dump(Zphp\select(['a' => $a, 'b' => $b]));
$a->send("first");
var_dump(Zphp\select([$a, $b]), count($a));

// a timeout returns null; zero polls without waiting
var_dump(Zphp\select([$a, $b], 0));
$t = hrtime(true);
var_dump(Zphp\select([$a, $b], 0.05), (hrtime(true) - $t) / 1e6 >= 45);

// a closed channel still hands out what it holds, then drops out
$b->send("last");
$b->close();
var_dump(Zphp\select(['a' => $a, 'b' => $b]), Zphp\select(['a' => $a, 'b' => $b], 0));
$a->close();
attempt(fn() => Zphp\select([$a, $b]));

// bad arguments
attempt(fn() => Zphp\select([]));
attempt(fn() => Zphp\select([new Zphp\Channel, "x"]));
attempt(fn() => Zphp\select("x"));
attempt(fn() => Zphp\select([new Zphp\Channel], -1));
// named arguments reach native constructors, methods, and functions in any order
$named = new Zphp\Channel(capacity: 2);
$named->send(timeout: 0.1, value: "by name");
var_dump(Zphp\select(timeout: 0, sources: ['n' => $named]));
$nb = Zphp\Buffer::fromString(bytes: "hello");
$nb->writeUInt8(value: 74, offset: 0);
var_dump($nb->slice(length: 2, offset: 0)->toString());
$np = new Zphp\Pool(queue: 3, workers: 1);
var_dump($np->workers());
$np->shutdown();
attempt(fn() => $named->send(valu: 1));
attempt(fn() => new Zphp\Buffer(size: 3));
// a fully qualified call works the same (a namespace declaration can't
// follow code in one file)
attempt(fn() => \Zphp\select([new \Zphp\Channel], 0));

$pool = new \Zphp\Pool(workers: 4, bootstrap: __DIR__ . "/worker.php");

// futures come back as themselves, ready to await, in completion order
$futures = ['slow' => $pool->submit('slow', [120]), 'fast' => $pool->submit('slow', [20]), 'mid' => $pool->submit('slow', [70])];
while ($futures) {
    [$key, $future] = \Zphp\select($futures);
    echo $key, ": ", $future->await(), " ", $future === $futures[$key] ? "same future" : "other", "\n";
    unset($futures[$key]);
}

// a failed or cancelled task is ready too; await says how it ended
$boom = $pool->submit('boom', ['from select']);
[$key, $f] = \Zphp\select(['boom' => $boom]);
try { $f->await(); } catch (\InvalidArgumentException $e) { echo "$key threw: ", $e->getMessage(), "\n"; }

// a value sent from another thread wakes a blocked select
$wake = new \Zphp\Channel(1);
$sender = $pool->submit('send_later', [$wake, 50, "woken"]);
$t = hrtime(true);
var_dump(\Zphp\select(['never' => new \Zphp\Channel(1), 'wake' => $wake]), (hrtime(true) - $t) / 1e6 >= 40);
$sender->await();

// progress from a running task alongside its future
$progress = new \Zphp\Channel(8);
$job = $pool->submit('report_progress', [$progress, 5]);
$seen = [];
while (true) {
    [$key, $value] = \Zphp\select(['progress' => $progress, 'job' => $job]);
    if ($key === 'job') break;
    $seen[] = $value;
}
while (($more = \Zphp\select([$progress], 0)) !== null) $seen[] = $more[1];
echo $job->await(), ": ", implode(",", $seen), "\n";

// consumers on several threads each receive a value exactly once
$jobs = new \Zphp\Channel(16);
$quit = new \Zphp\Channel(2);
$consumers = [$pool->submit('select_consumer', [$jobs, $quit]), $pool->submit('select_consumer', [$jobs, $quit])];
for ($i = 1; $i <= 200; $i++) $jobs->send($i);
while (count($jobs) > 0) usleep(1000);
usleep(20000);
$quit->send(true);
$quit->send(true);
$all = array_merge(...array_map(fn($c) => $c->await(), $consumers));
sort($all);
var_dump(count($all), $all === range(1, 200));

// two sources that are always ready both get a turn
$x = new \Zphp\Channel(100);
$y = new \Zphp\Channel(100);
for ($i = 0; $i < 100; $i++) { $x->send("x"); $y->send("y"); }
$picked = ['x' => 0, 'y' => 0];
for ($i = 0; $i < 100; $i++) $picked[\Zphp\select(['x' => $x, 'y' => $y])[0]]++;
var_dump($picked['x'] > 20 && $picked['y'] > 20);

// select with only a pending future times out and leaves it usable
$late = $pool->submit('slow', [100]);
var_dump(\Zphp\select([$late], 0.01), $late->await());
$pool->shutdown();
