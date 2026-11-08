<?php
// the collector raises its threshold after a run that frees almost nothing,
// and after one whose destructors refill the buffer, and lowers it again
// after runs that free plenty (php's gc_adjust_threshold)
var_dump(gc_status()['threshold']);
$live = [];
for ($i = 0; $i < 30000; $i++) $live[] = new stdClass;
// possible roots that are all alive
for ($round = 0; $round < 3; $round++) {
    foreach ($live as $o) { $x = $o; }
}
unset($x);
$st = gc_status();
var_dump($st['threshold'] > 10001, $st['runs'] >= 1);

class Cycle { public $self; function __construct() { $this->self = $this; } }
$before = gc_status()['threshold'];
for ($i = 0; $i < 200000; $i++) new Cycle;
var_dump(gc_status()['threshold'] < $before);

// destructors that make more garbage than a run frees
register_shutdown_function(function () { global $shutdown; $shutdown = true; });
class Canary {
    public $self;
    function __construct() { $this->self = $this; }
    function __destruct() { global $shutdown; if (!$shutdown) work(); }
}
function work() {
    global $live;
    new Canary;
    for ($i = 0; $i < 100; $i++) new Cycle;
    foreach (array_slice($live, 0, 10001) as $o) { $x = $o; }
}
$runs = gc_status()['runs'];
work();
foreach ($live as $o) { $x = $o; }
var_dump(gc_status()['runs'] - $runs <= 10);
echo "done\n";
