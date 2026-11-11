<?php
// an exception thrown by a destructor the collector runs reaches the code
// that ran the collection, gc_collect_cycles() or a statement whose
// releases filled the root buffer, also inside a fiber

class Cycle {
    public $self;
    public function __construct(public $name) {
        $this->self = $this;
    }
    public function __destruct() {
        echo "{$this->name} destructed\n";
        throw new Exception("from {$this->name}");
    }
}

try {
    new Cycle("explicit");
    gc_collect_cycles();
    echo "not reached\n";
} catch (Exception $e) {
    echo "caught ", $e->getMessage(), "\n";
}

$fiber = new Fiber(function () {
    try {
        new Cycle("in fiber");
        gc_collect_cycles();
        echo "not reached\n";
    } catch (Exception $e) {
        echo "caught ", $e->getMessage(), "\n";
    }
});
$fiber->start();

$objects = [];
for ($i = 0; $i < 20000; $i++) {
    $objects[] = new stdClass();
}
function fills_buffer() {
    global $objects;
    try {
        $copies = [...$objects];
        new Cycle("automatic");
        $copies = null;
        echo "not reached\n";
    } catch (Exception $e) {
        echo "caught ", $e->getMessage(), "\n";
    }
}
fills_buffer();
