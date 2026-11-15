<?php
// the collector marks a deep live graph in time linear in its size: an
// exception whose trace holds a deeply nested argument, and a cycle that
// reaches a deep chain, are collected quickly (the quadratic marking took
// over 30 seconds; a debug build on ci takes about 2)

function fail($a) { throw new Exception("x"); }

function nest($n) {
    $a = [];
    for ($i = 0; $i < $n; $i++) $a = [$a];
    return $a;
}

function depth($a) {
    $d = 0;
    while ($a) { $a = $a[0]; $d++; }
    return $d;
}

$start = microtime(true);
try {
    fail(nest(40000));
} catch (Exception $e) {
    echo "caught\n";
}
var_dump(gc_collect_cycles());
echo depth($e->getTrace()[0]['args'][0]), "\n";

$o = new stdClass;
$o->self = $o;
$o->e = $e;
unset($e);
$chain = nest(40000);
$keep = [$chain, $o];
unset($o);
var_dump(gc_collect_cycles());
echo depth($keep[0]), "\n";
echo get_class($keep[1]->e), "\n";

// the same graph once it is garbage
$o = $keep[1];
unset($keep);
unset($chain);
unset($o);
var_dump(gc_collect_cycles() > 40000);

$elapsed = microtime(true) - $start;
echo $elapsed < 10.0 ? "linear\n" : "slow: $elapsed\n";
