<?php
// gc_status()['running'] is true while the collector runs the garbage's
// destructors, and a collection started inside one does nothing

class Cyclic {
    public $other;
    public function __construct() {
        $this->other = new stdClass;
        $this->other->back = $this;
    }
    public function __destruct() {
        echo "destruct running=", var_export(gc_status()['running'], true), "\n";
        echo "nested collection: ", gc_collect_cycles(), "\n";
    }
}

var_dump(gc_status()['running']);
new Cyclic;
var_dump(gc_collect_cycles());
var_dump(gc_status()['running']);
