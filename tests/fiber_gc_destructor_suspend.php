<?php
// garbage collected while a fiber runs has its destructors called in a fiber
// of the collector's: one that suspends can be resumed later through the
// fiber it got from Fiber::getCurrent(), and the rest still run
class Node {
    public static int $count = 0;
    public $self;
    public function __construct() { $this->self = $this; }
    public function __destruct() {
        $id = self::$count++;
        echo "$id start\n";
        if ($id === 0) {
            global $parked;
            $parked = Fiber::getCurrent();
            echo 'in a fiber: ', var_export($parked !== null, true), "\n";
            echo 'value back: ', Fiber::suspend('parked'), "\n";
        }
        echo "$id end\n";
    }
}
$outer = new Fiber(function () {
    global $outer, $parked;
    for ($i = 0; $i < 3; $i++) new Node;
    echo 'collected ', gc_collect_cycles(), "\n";
    echo 'outer is the destructor fiber: ', var_export($parked === $outer, true), "\n";
    $parked->resume('resumed');
    echo 'parked terminated: ', var_export($parked->isTerminated(), true), "\n";
});
$outer->start();
for ($i = 0; $i < 2; $i++) new Node;
echo 'collected outside a fiber ', gc_collect_cycles(), "\n";
