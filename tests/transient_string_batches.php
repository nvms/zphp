<?php
function stringBatch(int $count): void {
    for ($i = 0; $i < $count; ++$i) {
        $a = 'temporary-' . $i;
        $b = $a . '-suffix';
        $c = 'prefix';
        $c .= $b;
        $c .= $i;
    }
}
$held = [];
for ($batch = 0; $batch < 8; ++$batch) {
    stringBatch(20000);
    $held[] = 'retained-' . $batch;
    gc_collect_cycles();
    echo 'batch:', $batch, ':', implode(',', $held), "\n";
}
