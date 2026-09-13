<?php
// cpu-bound scaling: the same work split over 1, 2, 4, and 8 workers
$tasks = 32;
$per_task = 300000;
foreach ([1, 2, 4, 8] as $workers) {
    $pool = new Zphp\Pool(workers: $workers, bootstrap: __DIR__ . "/worker.php");
    $start = hrtime(true);
    $futures = [];
    for ($i = 0; $i < $tasks; $i++) $futures[] = $pool->submit('spin', [$per_task]);
    foreach ($futures as $f) $f->await();
    $ms = (hrtime(true) - $start) / 1e6;
    printf("%d workers: %.0f ms\n", $workers, $ms);
    $pool->shutdown();
}
