<?php
// runs on the release build: after a warm-up, thousands more tasks with array
// payloads in both directions leave the process footprint where it was
// (memory_get_usage reports peak rss, so this is a retention check)
function big(int $n): array { return array_fill(0, $n, str_repeat("x", 64)); }
$pool = new Zphp\Pool(2, __DIR__ . "/worker.php");
for ($i = 0; $i < 500; $i++) { $pool->submit('big', [100])->await(); }
$before = memory_get_usage();
for ($i = 0; $i < 3000; $i++) { $pool->submit('big', [100])->await(); }
for ($i = 0; $i < 3000; $i++) { $pool->submit('count', [big(100)])->await(); }
for ($batch = 0; $batch < 15; $batch++) {
    for ($i = 0; $i < 200; $i++) { $pool->submit('str_repeat', ['x', 8000]); }
    while ($pool->collect(5.0)) {}
}
$stream = new Zphp\Channel(8);
for ($batch = 0; $batch < 10; $batch++) {
    $f = $pool->submit('produce_big', [$stream, 300]);
    for ($i = 0; $i < 300; $i++) { $stream->recv(); }
    $f->await();
}
for ($i = 0; $i < 2000; $i++) { $carrier = new Zphp\Channel(1); $carrier->send(['inner' => new Zphp\Channel(1)]); $carrier->recv()['inner']->trySend("x"); }
$scale = 3;
for ($i = 0; $i < 3000; $i++) { $pool->submit(function (int $n) use ($scale) { return big($n * $scale); }, [30])->await(); }
$growth = memory_get_usage() - $before;
echo $growth < 16 * 1024 * 1024 ? "memory bounded\n" : "memory grew by $growth\n";
exit($growth < 16 * 1024 * 1024 ? 0 : 1);
