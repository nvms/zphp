<?php
// A dead recursive closure must release its captures before GC recycles them.
function abandonedClosure() {
    $snapshot = [1, 2];
    $f = function () use (&$f, $snapshot) {};
}
for ($i = 0; $i < 100; ++$i) {
    abandonedClosure();
    gc_collect_cycles();
    gc_collect_cycles();
}
echo "recursive captures collected\n";

// Snapshot and reference-cell holders are distinct owning graph edges.
function liveClosures() {
    $value = [1];
    $snapshot = function () use ($value) { return $value; };
    $reference = function ($next) use (&$value) { $value = $next; return $value; };
    return [$snapshot, $reference];
}
[$snapshot, $reference] = liveClosures();
$reference([2, 3]);
gc_collect_cycles();
var_dump($snapshot(), $reference([4]));
gc_collect_cycles();
var_dump($snapshot());
unset($snapshot, $reference);
gc_collect_cycles();

class ClosureGcPayload {
    public static $destroyed = 0;
    public $callback;
    function __destruct() { ++self::$destroyed; gc_collect_cycles(); }
}
// Static cells belong to their closure, not to a permanent global GC root.
function staticCycle() {
    $f = function ($self = null) {
        static $payload;
        if ($self !== null) {
            $payload = new ClosureGcPayload();
            $payload->callback = $self;
        }
        return $payload !== null;
    };
    $f($f);
    return $f;
}
$live = staticCycle();
gc_collect_cycles();
var_dump($live(), ClosureGcPayload::$destroyed);
unset($live);
gc_collect_cycles();
gc_collect_cycles();
var_dump(ClosureGcPayload::$destroyed);
echo "done\n";

// An external alias to a captured cell keeps the closure reachable.
$f = function () use (&$f) { return 17; };
$alias =& $f;
unset($f);
gc_collect_cycles();
var_dump($alias());
unset($alias);
gc_collect_cycles();
gc_collect_cycles();
