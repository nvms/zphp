<?php
class LazyCycleNode { public int $value = 1; }
class LazyCycleHolder {
    public $object;
    public function __destruct() { echo "holder released\n"; }
}
function lazyCycle(bool $keepInitializer) {
    $holder = new LazyCycleHolder;
    $initializer = function ($object) use ($holder) { $object->value = 2; };
    $object = (new ReflectionClass(LazyCycleNode::class))->newLazyGhost($initializer);
    $holder->object = $object;
    return $keepInitializer ? $initializer : null;
}
$initializer = lazyCycle(false);
gc_collect_cycles();
echo "collected\n";
$initializer = lazyCycle(true);
gc_collect_cycles();
echo "retained\n";
$initializer = null;
gc_collect_cycles();
echo "collected again\n";
function lazyReferenceCycle(): void {
    $holder = new LazyCycleHolder;
    $holder->object = (new ReflectionClass(LazyCycleNode::class))->newLazyGhost(function ($object) use (&$holder) {});
}
lazyReferenceCycle();
gc_collect_cycles();
echo "reference cycle collected\n";
