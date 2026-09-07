<?php
class CycleCandidate {
    public $self;
    public function __destruct() { echo "released\n"; }
}
for ($round = 0; $round < 3; ++$round) {
    $object = new CycleCandidate;
    $object->self = $object;
    for ($i = 0; $i < 20000; ++$i) { $alias = $object; unset($alias); }
    gc_collect_cycles();
    echo "alive\n";
    unset($object);
    gc_collect_cycles();
    $array = [];
    $array['self'] = &$array;
    $array['object'] = new CycleCandidate;
    for ($i = 0; $i < 20000; ++$i) { $alias = $array; unset($alias); }
    gc_collect_cycles();
    echo "array alive\n";
    unset($array);
    gc_collect_cycles();
}
