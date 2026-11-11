<?php
// the collector calls every garbage destructor while all the garbage is
// intact, so a destructor can still call a closure its object holds

class Cycle {
    private $thing;
    public function __construct(public $n) {
        $obj = $this;
        $this->thing = function () use ($obj) {
            return $obj->n;
        };
    }
    public function __destruct() {
        echo "destructing ", ($this->thing)(), "\n";
    }
}

new Cycle(1);
new Cycle(2);
var_dump(gc_collect_cycles());
echo "OK\n";
