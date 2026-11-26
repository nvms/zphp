<?php
// a fiber destroyed while suspended runs its finally blocks with no caller
// below its own frames: traces and backtraces end there

function inner() {
    try {
        Fiber::suspend();
    } finally {
        foreach (debug_backtrace() as $frame) {
            echo $frame['function'], isset($frame['line']) ? " line {$frame['line']}" : " internal", "\n";
        }
        throw new Exception("from finally");
    }
}

function make() {
    $fiber = new Fiber(function () { inner(); });
    $fiber->start();
    return $fiber;
}

function release() {
    $fiber = make();
    try {
        unset($fiber);
    } catch (Exception $e) {
        echo $e->getMessage(), "\n", $e->getTraceAsString(), "\n";
    }
}

release();

// the gc's destructor fiber, suspended by a destructor and destroyed when
// it is released
class Cycle {
    public $self;
    public function __construct() {
        $this->self = $this;
    }
    public function __destruct() {
        try {
            Fiber::suspend();
        } finally {
            echo "finally\n";
            echo (new Exception)->getTraceAsString(), "\n";
            foreach (debug_backtrace() as $frame) {
                echo $frame['function'], "\n";
            }
        }
    }
}

$f = new Fiber(function () {
    new Cycle();
    gc_collect_cycles();
    echo "collected\n";
});
$f->start();
echo "end\n";
