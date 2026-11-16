<?php
// a result an expression statement discards is no possible root (php's FREE),
// a constructor's release of its object is one, and a fiber lets go of its
// callable as its function returns: the releases that fill the root buffer
// collect there, and a destructor's exception is thrown out of start()

class Cycle {
    public $self;
    public function __construct() {
        $this->self = $this;
    }
    public function __destruct() {
        echo "Cycle::__destruct\n";
        throw new Exception('Cycle::__destruct');
    }
}

class Plain {}
class WithCtor { public function __construct() {} }

$before = gc_status()['roots'];
$plain = [];
for ($i = 0; $i < 50; $i++) {
    $plain[] = new Plain();
}
echo "appended without constructor: ", gc_status()['roots'] - $before, "\n";
$built = [];
for ($i = 0; $i < 50; $i++) {
    $built[] = new WithCtor();
}
echo "appended with constructor: ", gc_status()['roots'] - $before, "\n";
$plain = $built = null;
gc_collect_cycles();

$objects = [];
for ($i = 0; $i < 10500; $i++) {
    $objects[] = new stdClass();
}

function create_fiber() {
    global $objects;
    $copies = [...$objects];
    return new Fiber(function () use ($copies) {
        new Cycle();
        echo "Return\n";
        return 42;
    });
}

$fiber = create_fiber();
try {
    $fiber->start();
    echo "Not reached\n";
} catch (Exception $e) {
    echo 'Caught: ', $e->getMessage(), "\n";
}
var_dump($fiber->isTerminated());

// a fiber's callable is gone once it ends, thrown or not
class Probe {
    public function __destruct() {
        echo "Probe::__destruct\n";
    }
}
$probe = new Probe();
$f = new Fiber(function () use ($probe) {
    echo "running\n";
});
$probe = null;
$f->start();
echo "after start\n";
$probe = new Probe();
$f = new Fiber(function () use ($probe) {
    throw new RuntimeException('thrown');
});
$probe = null;
try {
    $f->start();
} catch (RuntimeException $e) {
    echo 'Caught: ', $e->getMessage(), "\n";
}
echo "end\n";
